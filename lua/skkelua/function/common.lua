-- 確定・キャンセルなどの共通機能 (function/common.ts に相当)

local M = {}

--- 現在の状態を確定する
---@param context skkelua.Context
function M.kakutei(context)
	local state = context.state
	if state.type == "henkan" then
		local candidate = state.candidates[state.candidateIndex + 1]
		local candidate_mod = require("skkelua.candidate").modify_candidate(candidate, state.affix)
		if candidate then
			local lib = require("skkelua.store").get_library()
			lib:register_henkan_result(state.mode, state.word, candidate)
			context.lastCandidate = {
				type = state.mode,
				word = state.word,
				candidate = candidate,
			}
		end
		local okuri_str = state.converter and state.converter(state.okuriFeed) or state.okuriFeed
		local ret = (candidate_mod or "error") .. okuri_str
		context:kakutei_with_undo_point(ret)
	elseif state.type == "input" then
		require("skkelua.function.input").kakutei_feed(context)
		local result = state.henkanFeed .. state.okuriFeed .. state.feed
		-- 接頭辞・接尾辞入力のマーカー ">" は見出し検索用のもので、
		-- 候補を選ばないかな確定の文字列には含めない
		if state.affix == "suffix" then
			result = result:gsub("^>", "")
		elseif state.affix == "prefix" then
			result = result:gsub(">$", "")
		end
		if state.converter then
			result = state.converter(result)
		end
		context:kakutei(result)
	else
		vim.notify(
			("initializing unknown phase state: %s"):format(vim.inspect(state)),
			vim.log.levels.WARN
		)
	end
	require("skkelua.mode").initialize_state_with_abbrev(context, { "converter", "table" })
end

--- 確定キーの処理 (確定する物が無い状態ではひらがなモードに戻す)
--- この動作は ddskk に存在する
---@param context skkelua.Context
function M.kakutei_key(context)
	local state = context.state
	if state.type == "input" and state.mode == "direct" and state.feed == "" then
		require("skkelua.function.mode").hirakana(context)
		return
	end
	M.kakutei(context)
end

--- 改行キー
---@param context skkelua.Context
function M.newline(context)
	local config = require("skkelua.config").config
	local insert_newline = not (
		config.eggLikeNewline
		and (
			context.state.type == "henkan"
			or (context.state.type == "input" and context.state.mode ~= "direct")
		)
	)
	M.kakutei(context)
	if insert_newline then
		context:kakutei("\n")
	end
end

--- キャンセル
---@param context skkelua.Context
function M.cancel(context)
	local config = require("skkelua.config").config
	local mode = require("skkelua.mode")
	local state = context.state
	if state.type == "input" and state.mode == "direct" and context.vimMode == "c" then
		context:kakutei("\3") -- <C-c>
	end
	if config.immediatelyCancel then
		mode.initialize_state_with_abbrev(context)
		return
	end
	if state.type == "input" then
		mode.initialize_state_with_abbrev(context)
	elseif state.type == "henkan" then
		context.state.type = "input"
	end
end

--- 変換中なら確定してから空白を入力する (pureSpace 用)。
--- kana table 経由でも keymap 経由でも呼ばれるため、キー引数には
--- 依存せず空白固定で挿入する
---@param context skkelua.Context
function M.kakutei_space(context)
	local state = context.state
	if state.type == "henkan" or (state.type == "input" and state.mode ~= "direct") then
		M.kakutei(context)
	end
	context:kakutei(" ")
end

--- 変換中なら確定し、直接入力ではキー本来の動作に任せる (<C-y> 用)。
--- 補完候補の選択中は handle_impl が native の確定へパススルーするため
--- ここへは来ない。判定をすり抜けても direct 分岐が生キーを feed するので
--- native の確定として動作する
---@param context skkelua.Context
---@param key string
function M.kakutei_pass_through(context, key)
	local state = context.state
	if state.type == "input" and state.mode == "direct" then
		context:kakutei(key)
		return
	end
	M.kakutei(context)
end

--- 変換中は何もせず、直接入力ではキー本来の動作に任せる。
--- マップしないと pre-edit を壊す特殊キー (Tab など) の保護用
---@param context skkelua.Context
---@param key string
function M.pass_through(context, key)
	local state = context.state
	if state.type == "input" and state.mode == "direct" then
		-- 補完の選択挿入中 (バッファが候補 word に置き換わり、prevInput
		-- 不一致で direct へリセット済み) もバッファを崩すため無視する
		if require("skkelua.lsp").selected_word() then
			return
		end
		context:kakutei(key)
	end
end

--- 変換中の入力 (pre-edit) を全て削除する。
--- 変換中でなければキー本来の動作 (単語削除など) に任せる
---@param context skkelua.Context
---@param key string
function M.delete_pre_edit(context, key)
	local state = context.state
	if state.type == "input" and state.mode == "direct" then
		-- insertOnSelect の選択挿入中はバッファが候補 word に置き換わって
		-- おり、prevInput 不一致で state は direct へリセット済み。
		-- 挿入中の word を表示中テキストとして同期し、まとめて削除する
		local word = require("skkelua.lsp").selected_word()
		if word then
			context.preEdit:sync(word)
			return
		end
		context:kakutei(key)
		return
	end
	require("skkelua.mode").initialize_state_with_abbrev(context)
end

--- 候補を辞書から削除する。
--- pum で自前候補にフォーカスしただけ (insertOnSelect や手動ナビゲーションで
--- prevInput 不一致が起き、henkan から direct へリセット済み) でも、フォーカス中の
--- 候補を削除対象にする。フォーカス中候補も lastCandidate も無ければ
--- キー本来の動作 (かな入力) に任せる。
--- 削除後は ▽henkanFeed (未変換の見出し語入力) へ戻し、そのまま編集・
--- 再変換を続けられるようにする
---@param context skkelua.Context
---@param key string
function M.purge_candidate(context, key)
	local state = context.state
	local type_, word, candidate
	local restore_mode, restore_henkan_feed, restore_okuri_feed
	if state.type == "henkan" then
		type_ = state.mode
		word = state.word
		candidate = state.candidates[state.candidateIndex + 1]
		restore_mode, restore_henkan_feed, restore_okuri_feed = state.mode, state.henkanFeed, state.okuriFeed
	elseif state.type == "input" then
		if state.mode == "direct" then
			local sel_word, data = require("skkelua.lsp").selected_word()
			if data then
				type_, word, candidate = data.type, data.midasi, data.word
				-- pum が直接書き換えたバッファのテキストを表示中として認識させ、
				-- 削除対象にする (delete_pre_edit と同じ再同期パターン)
				context.preEdit:sync(sel_word)
				restore_mode = data.type
				if data.type == "okuriari" then
					-- data.midasi は okuri.get_okuri_str が組み立てた
					-- 語幹 + 送り仮名アルファベット (1 文字) の辞書見出し形式なので、
					-- 末尾を落として語幹を取り出す。送り仮名の生かなは data.okuri にある
					restore_henkan_feed = data.midasi:sub(1, -2)
					restore_okuri_feed = data.okuri or ""
				else
					restore_henkan_feed = data.midasi
					restore_okuri_feed = ""
				end
			elseif context.lastCandidate.word ~= "" then
				type_ = context.lastCandidate.type
				word = context.lastCandidate.word
				candidate = context.lastCandidate.candidate
			end
		end
		if not word then
			require("skkelua.function.input").kana_input(context, key)
			return
		end
	else
		vim.print("purgeCandidate: reach illegal state")
		vim.print(context)
		return
	end
	if word == "" then
		return
	end
	local msg = ("Really purge? %s /%s/"):format(word, candidate)
	if vim.fn.confirm(msg, "&Yes\n&No\n", 2) == 1 then
		local lib = require("skkelua.store").get_library()
		lib:purge_candidate(type_, word, candidate)
		if restore_henkan_feed then
			state.mode = restore_mode
			state.henkanFeed = restore_henkan_feed
			state.okuriFeed = restore_okuri_feed
			require("skkelua.state").initialize_state(state, { "mode", "henkanFeed", "okuriFeed" })
		else
			require("skkelua.state").initialize_state(state)
		end
		context.lastCandidate.word = ""
	end
end

return M
