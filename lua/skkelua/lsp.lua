-- 変換候補を Neovim builtin 補完へ流す in-process LSP サーバー
--
-- 変換入力中 (▽かんじ) に、見出しを前方一致検索した変換候補を
-- textDocument/completion の結果として返す。候補を確定すると
-- CompleteDone でユーザー辞書へ登録される。

local M = {}

local CLIENT_NAME = "skkelua"

local function completion_config()
	return require("skkelua.config").config.completion
end

--- buffer-local 'completeopt' を調整する。
--- 候補が 1 つだけでも pum を出すよう常に menuone を足す
--- (noselect は menu/menuone との併用でしか効かない)。
--- insertOnSelect では選択と同時に挿入するために noinsert を外し、
--- タイプ中に第一候補が勝手に入らないよう通常は noselect を足す。
--- auto_select (送り仮名確定直後) の応答では noselect も外し、
--- 第一候補が自動選択 + 挿入されるようにする
---@param buf integer
---@param auto_select? boolean
local function set_completeopt(buf, auto_select)
	local instant_insert = completion_config().insertOnSelect
	local values = { "menuone" }
	if instant_insert and not auto_select then
		values[#values + 1] = "noselect"
	end
	for _, o in ipairs(vim.opt_global.completeopt:get()) do
		local drop = o == "menuone" or (instant_insert and (o == "noinsert" or o == "noselect"))
		if not drop then
			values[#values + 1] = o
		end
	end
	vim.api.nvim_set_option_value("completeopt", table.concat(values, ","), { buf = buf })
end

--- vim.snippet の特殊文字 ($ と \) をエスケープする
---@param s string
---@return string
local function escape_snippet(s)
	return (s:gsub("[\\%$]", "\\%0"))
end

--- ひらがな (+ 長音・マーカー・送りローマ字) を triggerCharacters として列挙する
---@return string[]
local function trigger_characters()
	local chars = {}
	-- ぁ (U+3041) 〜 ゖ (U+3096)
	for cp = 0x3041, 0x3096 do
		chars[#chars + 1] = vim.fn.nr2char(cp)
	end
	chars[#chars + 1] = "ー"
	chars[#chars + 1] = require("skkelua.config").config.markerHenkan
	-- 候補選択 (▼送る) への遷移は markerHenkanSelect の挿入で検知する
	chars[#chars + 1] = require("skkelua.config").config.markerHenkanSelect
	-- 送りあり入力 (▽おく*r) で挿入されるのは "*" と送りのローマ字。
	-- 以降の絞り込みは isIncomplete による再リクエストが担うが、
	-- 初回トリガーのためにこれらも含める
	chars[#chars + 1] = "*"
	for i = 0, 25 do
		chars[#chars + 1] = string.char(97 + i) -- a-z
	end
	return chars
end

---@class skkelua.LspCandidate
---@field word string 辞書上の候補原文 (注釈付き)
---@field midasi string 辞書の見出し
---@field okuri string 送り仮名 (送りなしは "")
---@field type skkelua.HenkanType
---@field affix? skkelua.AffixType
---@field rank? number 並び順の決定に使うランク (大きいほど上)

--- 送りなし変換入力 (▽かんじ) の候補: 見出しの前方一致検索
--- (@ddc-sources/skkeleton の gather に相当)。
--- ユーザー辞書で確定済みの候補 (ランク持ち) を確定が新しい順に先頭へ置き、
--- 残りは見出しの辞書順で並べる
---@return skkelua.LspCandidate[]
local function okurinasi_candidates()
	local skkelua = require("skkelua")
	local completions = skkelua.get_completion_result()
	table.sort(completions, function(a, b)
		return a[1] < b[1]
	end)
	local ranks = {}
	for _, e in ipairs(skkelua.get_ranks()) do
		ranks[e[1]] = e[2]
	end
	-- ランクを持たない候補はランク持ちの末尾より配置する。
	-- 見出しの辞書順を保つよう先頭から順に負の方向にランクを振っていく
	local global_rank = -1
	local result = {}
	for _, entry in ipairs(completions) do
		local midasi, words = entry[1], entry[2]
		for _, word in ipairs(words) do
			local rank = ranks[word]
			if rank == nil then
				rank = global_rank
				global_rank = global_rank - 1
			end
			result[#result + 1] = { word = word, midasi = midasi, okuri = "", type = "okurinasi", rank = rank }
		end
	end
	table.sort(result, function(a, b)
		return a.rank > b.rank
	end)
	return result
end

--- feed (送りのローマ字) から確定しうる送り仮名を列挙する
---@param kana_table skkelua.KanaTable
---@param feed string
---@return string[]
local function feed_kana_candidates(kana_table, feed)
	local kanas = {}
	local seen = {}
	for _, e in ipairs(kana_table) do
		-- feed に前方一致し、残余 feed を持たないエントリだけが送り仮名として完成する
		if vim.startswith(e[1], feed) and type(e[2]) == "table" and e[2][2] == "" then
			local kana = e[2][1]
			if kana ~= "" and not seen[kana] then
				seen[kana] = true
				kanas[#kanas + 1] = kana
			end
		end
	end
	return kanas
end

--- 候補選択中 (▼送る) の候補: 引いてある変換候補をそのまま並べる
---@return skkelua.LspCandidate[]
local function henkan_candidates()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "henkan" then
		return {}
	end
	local okuri = state.converter and state.converter(state.okuriFeed) or state.okuriFeed
	local result = {}
	for _, word in ipairs(state.candidates) do
		result[#result + 1] = {
			word = word,
			midasi = state.word,
			okuri = okuri,
			type = state.mode,
			affix = state.affix,
		}
	end
	return result
end

--- 送りあり変換入力 (▽おく*r) の候補:
--- 送りのローマ字からありうる送り仮名を列挙し、語幹 + 送り仮名の完成形を出す
---@return skkelua.LspCandidate[]
local function okuriari_candidates()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "input" or state.previousFeed then
		return {}
	end
	local lib = require("skkelua.store").get_library()
	local get_okuri_str = require("skkelua.okuri").get_okuri_str

	local result = {}
	local function collect(midasi, okuri)
		for _, word in ipairs(lib:get_henkan_result("okuriari", midasi)) do
			result[#result + 1] = { word = word, midasi = midasi, okuri = okuri, type = "okuriari" }
		end
	end

	if state.okuriFeed ~= "" then
		-- 送り仮名の先頭が確定済み (immediatelyOkuriConvert=false の「っ」など)。
		-- 見出しは確定しているので、残り feed の展開だけ行う
		local midasi = get_okuri_str(state.henkanFeed, state.okuriFeed)
		if state.feed == "" then
			collect(midasi, state.okuriFeed)
		else
			for _, kana in ipairs(feed_kana_candidates(state.table, state.feed)) do
				collect(midasi, state.okuriFeed .. kana)
			end
		end
	elseif state.feed ~= "" then
		for _, kana in ipairs(feed_kana_candidates(state.table, state.feed)) do
			collect(get_okuri_str(state.henkanFeed, kana), kana)
		end
	end
	return result
end

--- pum で選択中の自前候補の word がカーソル前に挿入されていればそれを返す。
--- insertOnSelect の選択挿入はバッファ上の pre-edit を候補 word で
--- 置き換えるため、その間に届いた再リクエストは pre-edit を見つけられない
---@param before_cursor string
---@return string? word
---@return table? data 候補の data (skkelua/midasi/word/type)
local function selected_word(before_cursor)
	if vim.fn.pumvisible() == 0 then
		return nil
	end
	local info = vim.fn.complete_info({ "selected", "items" })
	local sel = (info.selected or -1) >= 0 and info.items[info.selected + 1] or nil
	local word = sel and sel.word
	if not word or word == "" or not vim.endswith(before_cursor, word) then
		return nil
	end
	local item = vim.tbl_get(sel, "user_data", "nvim", "lsp", "completion_item")
	if not (item and vim.tbl_get(item, "data", "skkelua")) then
		return nil
	end
	return word, item.data
end

--- complete_info() の item が skkelua の [辞書登録] 項目かどうか
---@param pum_item? table
---@return boolean
function M.is_register_item(pum_item)
	local data = vim.tbl_get(pum_item or {}, "user_data", "nvim", "lsp", "completion_item", "data")
	return type(data) == "table" and data.skkelua == true and data.register == true
end

--- pum で選択中の自前候補の word が現在のカーソル前に挿入されていれば返す
--- (deletePreEdit の削除対象判定や、選択挿入中の接尾辞開始に使う)
---@return string? word
---@return table? data
function M.selected_word()
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = (vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false) or {})[1] or ""
	return selected_word(line:sub(1, pos[2]))
end

--- 補完候補を組み立てる。
--- nil を返した場合は応答自体を保留する (complete() を走らせない)
---@return table? CompletionList
local function make_completion_list()
	local empty = { isIncomplete = true, items = {} }
	local skkelua = require("skkelua")
	local phase = skkelua.phase()
	local supported = phase == "input:okurinasi" or phase == "input:okuriari" or phase == "henkan"
	if not skkelua.is_enabled() or not supported then
		return empty
	end
	local pre_edit = skkelua.get_pre_edit()
	-- 変換入力中はかなが無ければ出さない (henkan は候補が引けているので不要)
	if pre_edit == "" or (phase ~= "henkan" and skkelua.get_prefix() == "") then
		return empty
	end

	-- カーソル前のテキストが pre-edit (▽かんじ) で終わっていることを確認し、
	-- その開始位置を置換範囲にする。
	-- Note: params.position は使わない。pre-edit の再描画 (BS + 再挿入) は
	--       InsertCharPre ごとにリクエストを積むので、後発の処理時点では
	--       バッファが先へ進んでいることがある。クライアント (builtin) も
	--       応答を処理時点のカーソルで解釈するため、常に現在位置で組み立てる
	local buf = vim.api.nvim_get_current_buf()
	local pos = vim.api.nvim_win_get_cursor(0)
	local row = pos[1] - 1
	local col = pos[2] -- utf-8 (byte)
	local line = (vim.api.nvim_buf_get_lines(buf, row, row + 1, false) or {})[1] or ""
	local before_cursor = line:sub(1, col)
	if not vim.endswith(before_cursor, pre_edit) then
		-- insertOnSelect の選択挿入中 (バッファは pre-edit でなく候補 word) に
		-- 届いた後発リクエスト。pre-edit の再描画は InsertCharPre ごとに
		-- リクエストを積むため、選択挿入を起こした応答の後にも同じ状態への
		-- リクエストが残っている。ここで空を返すと complete() が pum を閉じ、
		-- 同じ候補を返し直しても complete() の再実行で typed text が候補 word に
		-- すり替わり <C-p>/<C-e> で pre-edit に戻れなくなる。
		-- 応答を保留して、表示中の pum と選択状態をそのまま保つ
		if selected_word(before_cursor) then
			return nil
		end
		return empty
	end
	local start_col = col - #pre_edit
	local range = {
		start = { line = row, character = start_col },
		["end"] = { line = row, character = col },
	}

	local marker = require("skkelua.config").config.markerHenkan
	local modify_candidate = require("skkelua.candidate").modify_candidate

	local candidates
	if phase == "input:okurinasi" then
		candidates = okurinasi_candidates()
	elseif phase == "input:okuriari" then
		candidates = okuriari_candidates()
	else
		candidates = henkan_candidates()
	end

	local instant_insert = completion_config().insertOnSelect
	-- typed text (pre-edit) に ASCII 英数字が含まれるとクライアント側の
	-- fuzzy フィルタが有効になり、素の label ではマッチしなくなる。
	-- その場合は label に pre-edit を前置してフィルタを通し、
	-- 表示は convert フック (enable 時に登録) で候補のみへ戻す
	local prefixed_label = pre_edit:find("%w") ~= nil

	-- deferOkuri で送り仮名が確定した直後 (▽おく*る) は、第一候補を
	-- 自動選択して即挿入する (completeopt の noselect をこの応答だけ外す)
	local auto_select = false
	if instant_insert and phase == "input:okuriari" then
		local state = require("skkelua.store").get_context().state
		auto_select = completion_config().deferOkuri and state.feed == "" and state.okuriFeed ~= ""
	end
	set_completeopt(buf, auto_select)

	local items = {}
	local seen = {}
	for _, c in ipairs(candidates) do
		-- 送りありは語幹 + 送り仮名の完成形を挿入する
		local display = (modify_candidate(c.word, c.affix) or c.word) .. c.okuri
		if not seen[display] then
			seen[display] = true
			local annotation = c.word:match(";(.*)$")
			local item = {
				label = display,
				labelDetails = annotation and { description = annotation } or nil,
				detail = c.midasi,
				kind = vim.lsp.protocol.CompletionItemKind.Text,
				-- クライアント (builtin) は sortText (無ければ label) で並べ替える。
				-- 辞書順 (ユーザー辞書 -> グローバル辞書のマージ順) を保つよう
				-- 応答順の連番を振る
				sortText = ("%05d"):format(#items + 1),
				textEdit = {
					range = range,
					newText = display,
				},
				-- okuri (送り仮名の生かな) は purgeCandidate が ▽henkanFeed*okuriFeed
				-- を組み立て直すのに使う (midasi は語幹 + 送り仮名アルファベットの
				-- 辞書見出し形式で、そのままでは送り仮名を分離できない)
				data = { skkelua = true, midasi = c.midasi, word = c.word, type = c.type, okuri = c.okuri },
			}
			if instant_insert then
				-- insertOnSelect: filterText を持たせないことで、クライアントの
				-- 挿入 word が newText (候補そのもの) になり、<C-n> での
				-- 選択と同時に pre-edit 全体が候補へ置き換わる
				item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText
				if prefixed_label then
					item.label = pre_edit .. display
					item.data.display = display
				end
			else
				-- クライアントは typed text と filterText を照合する。
				-- 送りなし入力中は続きのかな入力で絞り込めるよう marker + 見出し、
				-- それ以外 (送りあり入力・候補選択) は pre-edit そのもの
				-- (絞り込みは isIncomplete の再リクエストが担う)
				item.filterText = phase == "input:okurinasi" and (marker .. c.midasi) or pre_edit
				-- Note: PlainText だと word が filterText に fallback した場合に
				--       newText が適用されない (単なる再挿入になる)。
				--       Snippet format は確定時に挿入 word を削除して
				--       newText を展開するため、pre-edit を候補で置換できる
				item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
				item.textEdit.newText = escape_snippet(display)
			end
			items[#items + 1] = item
		end
	end

	-- 新しい読みを登録する項目を末尾に置く (候補が無い読みでも pum が開く)。
	-- 挿入テキストは pre-edit 自身にして、フォーカスや確定でバッファが
	-- 変わらないようにする。確定すると CompleteDone から登録プロンプトが開く
	-- (登録プロンプトの中ではネストしたプロンプトが積まれる)。
	local state = require("skkelua.store").get_context().state
	local registrable = true
	local midasi
	if phase == "henkan" then
		midasi = state.word
	elseif phase == "input:okuriari" then
		-- 送り仮名が確定するまでは登録する読みが定まらない
		registrable = registrable and state.feed == "" and state.okuriFeed ~= ""
		midasi = registrable and require("skkelua.okuri").get_okuri_str(state.henkanFeed, state.okuriFeed)
	else
		midasi = state.henkanFeed
	end
	if registrable then
		local item = {
			label = "[辞書登録]",
			detail = midasi,
			kind = vim.lsp.protocol.CompletionItemKind.Text,
			sortText = ("%05d"):format(#items + 1),
			textEdit = {
				range = range,
				newText = pre_edit,
			},
			data = { skkelua = true, register = true },
		}
		if instant_insert then
			item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText
			if prefixed_label then
				item.label = pre_edit .. item.label
				item.data.display = "[辞書登録]"
			end
		else
			item.filterText = pre_edit
			item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
			item.textEdit.newText = escape_snippet(pre_edit)
		end
		items[#items + 1] = item
	end

	return { isIncomplete = true, items = items }
end

--------------------------------------------------------------------
-- in-process server
--------------------------------------------------------------------

---@return fun(dispatchers: table): table
local function new_server()
	return function(dispatchers)
		local closing = false
		local srv = {}
		srv.request = vim.schedule_wrap(function(method, params, handler)
			if method == "initialize" then
				handler(nil, {
					capabilities = {
						positionEncoding = "utf-8",
						completionProvider = {
							triggerCharacters = trigger_characters(),
						},
					},
				})
			elseif method == "textDocument/completion" then
				local list = make_completion_list()
				-- nil は応答保留 (選択挿入中のバースト)。放置されたリクエストは
				-- クライアントが次の trigger 時に cancel してくれる
				if list then
					table.insert(M._requests, { params = params, items = #list.items })
					handler(nil, list)
				end
			elseif method == "shutdown" then
				handler(nil, nil)
			end
		end)
		function srv.notify(method, _)
			if method == "exit" then
				dispatchers.on_exit(0, 15)
			end
		end
		function srv.is_closing()
			return closing
		end
		function srv.terminate()
			closing = true
		end
		return srv
	end
end

--------------------------------------------------------------------
-- attach / detach
--------------------------------------------------------------------

--- 候補確定時にユーザー辞書へ登録する
--- (テスト用に reason と completed_item を注入できるよう分離している)
---@param reason? string v:event.reason ("accept"/"cancel"/"discard")
---@param completed_item? table v:completed_item
function M._on_complete_done(reason, completed_item)
	-- <Esc>/<C-e> などで確定せず閉じた場合 (cancel/discard) は登録しない。
	-- reason が取れない環境では従来通り登録する
	if reason ~= nil and reason ~= "accept" then
		return
	end
	local item = vim.tbl_get(completed_item or {}, "user_data", "nvim", "lsp", "completion_item")
	local data = item and item.data
	if not (data and data.skkelua) then
		return
	end
	if data.register then
		-- [辞書登録] 項目: ins-completion の終了処理から抜けてから
		-- 登録プロンプトを開く。挿入テキストが pre-edit のままなので
		-- handle 側では変換入力の続きとして registerWord が実行される
		vim.schedule(function()
			require("skkelua").handle("handleKey", { ["function"] = "registerWord" })
		end)
		return
	end
	require("skkelua").complete_callback(data.midasi, data.word, data.type)
end

local function on_complete_done()
	M._on_complete_done(vim.tbl_get(vim.v.event, "reason"), vim.v.completed_item)
end


--- buffer-local 'completeopt' をグローバル値に戻す
---@param buf integer
local function restore_completeopt(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("setlocal completeopt<")
		end)
	end
end

--- ASCII 混じり pre-edit ではフィルタを通すため label に pre-edit を
--- 前置している。pum の表示 (abbr) は候補そのものへ戻す。
--- また detail (見出し) はクライアントが info に写し、'completeopt' の
--- popup で候補選択のたびにフロートとして出てしまうため、常に空へ戻す
---@param item table lsp.CompletionItem
---@return table
local function convert_item(item)
	local display = vim.tbl_get(item, "data", "display")
	return { info = "", abbr = display }
end

---@param client_id integer
---@param buf integer
local function enable_completion(client_id, buf)
	-- Note: builtin の completion.enable は「最初に buf_handle を作った呼び出しの
	--       opts」でバッファの補完動作が固定される。有効化・無効化サイクルを
	--       冪等にするため、一度無効化してから autotrigger 付きで登録し直す
	--       (それでも他の設定が同一バッファへ opts 無しで enable(true) を呼ぶと
	--       autotrigger は失われる。doc の注意書きを参照)
	vim.lsp.completion.enable(false, client_id, buf)
	vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true, convert = convert_item })
	set_completeopt(buf, false)
	vim.api.nvim_create_autocmd("CompleteDone", {
		group = vim.api.nvim_create_augroup("skkelua-lsp-complete-done", { clear = true }),
		callback = on_complete_done,
	})
end

--- 現在のバッファで補完を有効にする (skkelua-enable-post から呼ばれる)
function M.attach()
	if not completion_config().enabled then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local client_id = vim.lsp.start({
		name = CLIENT_NAME,
		cmd = new_server(),
	}, { bufnr = buf })
	if not client_id then
		return
	end
	-- Note: triggerCharacters は completion.enable 時に server_capabilities から
	--       読まれるため、initialize 完了前に呼ぶと autotrigger が働かない。
	--       未初期化の場合は LspAttach (setup_autocmds で登録) に任せる
	local client = vim.lsp.get_client_by_id(client_id)
	if client and client.initialized then
		enable_completion(client_id, buf)
	end
end

--- 現在のバッファで補完を明示的にトリガーする。
--- autotrigger はトリガー文字のタイプでしか働かないため、辞書登録の
--- キャンセルなどタイプを伴わずに pre-edit が復元された時に呼ぶ
function M.trigger()
	if not completion_config().enabled or vim.fn.mode() ~= "i" then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local client = vim.lsp.get_clients({ name = CLIENT_NAME, bufnr = buf })[1]
	if not client then
		return
	end
	vim.lsp.completion.get()
end

--- 現在のバッファで補完を無効にする (skkelua-disable-post から呼ばれる)
function M.detach()
	local buf = vim.api.nvim_get_current_buf()
	local client = vim.lsp.get_clients({ name = CLIENT_NAME, bufnr = buf })[1]
	if client then
		vim.lsp.completion.enable(false, client.id, buf)
	end
	restore_completeopt(buf)
end

--- 有効化・無効化に連動する autocmd を登録する (plugin/skkelua.lua から呼ばれる)
function M.setup_autocmds()
	local group = vim.api.nvim_create_augroup("skkelua-lsp", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "skkelua-enable-post",
		callback = function()
			M.attach()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "skkelua-disable-post",
		callback = function()
			M.detach()
		end,
	})
	-- initialize 完了後の attach を拾って autotrigger を有効化する
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if client and client.name == CLIENT_NAME then
				enable_completion(ev.data.client_id, ev.buf)
			end
		end,
	})
end

--- テスト用: completion list を直接組み立てる
function M._make_completion_list()
	return make_completion_list()
end

-- テスト用: 処理した completion リクエストの記録
M._requests = {}

return M
