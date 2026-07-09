-- 変換の開始・候補送り (function/henkan.ts に相当)

local util = require("skkelua.util")

local M = {}

-- henkanFirst の再入防止フラグ (TS 版の Mutex に相当)
-- ユーザーが key 単体に henkanFirst を振っていると kana_input 経由で
-- 無限ループを起こすので、繰り返し呼ばれた場合は直接入力にフォールバックする
local henkan_locked = false

--- input state を候補未取得の henkan state へ遷移させる
---@param context skkelua.Context
---@return skkelua.HenkanState
local function to_henkan_state(context)
	local state = context.state --[[@as skkelua.HenkanState]]
	state.type = "henkan"
	state.candidates = {}
	state.candidateIndex = -1

	local word
	if state.mode == "okurinasi" then
		word = state.henkanFeed
	else
		word = require("skkelua.okuri").get_okuri_str(state.henkanFeed, state.okuriFeed)
	end
	state.word = word
	if
		state.affix == nil
		and not state.directInput
		and (state.mode == "okurinasi" or state.mode == "okuriari")
	then
		-- When user manually uses henkanPoint,
		-- henkanFeed like `>prefix` and `suffix>` may
		-- reach here with undefined affix
		if state.henkanFeed:match(">$") then
			state.affix = "prefix"
		elseif state.henkanFeed:match("^>") then
			state.affix = "suffix"
		else
			state.affix = nil
		end
	end
	return state
end

--- 変換を開始する
---@param context skkelua.Context
---@param key string
function M.henkan_first(context, key)
	if context.state.type ~= "input" then
		return
	end

	local input_fn = require("skkelua.function.input")
	input_fn.kakutei_feed(context)

	if context.state.mode == "direct" then
		if henkan_locked then
			context:kakutei(key)
		else
			henkan_locked = true
			local ok, err = pcall(input_fn.kana_input, context, key)
			henkan_locked = false
			if not ok then
				error(err)
			end
		end
		return
	end

	if context.state.henkanFeed == "" then
		return
	end

	local state = to_henkan_state(context)
	local lib = require("skkelua.store").get_library()
	state.candidates = lib:get_henkan_result(state.mode, state.word)
	M.henkan_forward(context)
end

--- 変換候補を経由せず辞書登録プロンプトを開く
--- (補完メニュー末尾の [辞書登録] 項目から呼ばれる)
---@param context skkelua.Context
function M.register_word_first(context)
	local from_input = context.state.type == "input"
	if from_input then
		local state = context.state
		if state.mode == "direct" or state.henkanFeed == "" then
			return
		end
		require("skkelua.function.input").kakutei_feed(context)
		to_henkan_state(context)
	end
	if context.state.type ~= "henkan" then
		return
	end
	if not require("skkelua.function.dictionary").register_word(context) then
		-- キャンセル時: 変換入力から来た場合は変換入力の表示へ戻す
		if from_input then
			context.state.type = "input"
		end
	end
end

--- 次候補へ進む
---@param context skkelua.Context
function M.henkan_forward(context)
	local config = require("skkelua.config").config
	local state = context.state
	if state.type ~= "henkan" then
		return
	end
	local old_candidate_index = state.candidateIndex
	if state.candidateIndex >= config.showCandidatesCount then
		state.candidateIndex = state.candidateIndex + 7
	else
		state.candidateIndex = state.candidateIndex + 1
	end
	if #state.candidates <= state.candidateIndex then
		if require("skkelua.function.dictionary").register_word(context) then
			return
		end
		state.candidateIndex = old_candidate_index
		if state.candidateIndex == -1 then
			context.state.type = "input"
		end
	end
	if state.candidateIndex >= config.showCandidatesCount then
		M.show_candidates(state)
	end
end

--- 前候補へ戻る
---@param context skkelua.Context
function M.henkan_backward(context)
	local config = require("skkelua.config").config
	local state = context.state
	if state.type ~= "henkan" then
		return
	end
	if state.candidateIndex >= config.showCandidatesCount then
		state.candidateIndex = math.max(state.candidateIndex - 7, config.showCandidatesCount - 1)
	else
		state.candidateIndex = state.candidateIndex - 1
	end
	if state.candidateIndex < 0 then
		context.state.type = "input"
		return
	end
	if state.candidateIndex >= config.showCandidatesCount then
		M.show_candidates(state)
	end
end

--- 候補一覧ポップアップを表示する
---@param state skkelua.HenkanState
function M.show_candidates(state)
	local config = require("skkelua.config").config
	local modify_candidate = require("skkelua.candidate").modify_candidate
	local idx = state.candidateIndex
	local list = {}
	for i = 1, 7 do
		local c = state.candidates[idx + i]
		if not c then
			break
		end
		list[#list + 1] = ("%s: %s"):format(
			config.selectCandidateKeys:sub(i, i),
			modify_candidate(c, state.affix)
		)
	end
	require("skkelua.popup").open(list)
end

--- 候補選択中のキー入力
---@param context skkelua.Context
---@param key string
function M.henkan_input(context, key)
	local config = require("skkelua.config").config
	local common = require("skkelua.function.common")
	local state = context.state --[[@as skkelua.HenkanState]]
	if state.candidateIndex >= config.showCandidatesCount then
		local cand_idx = (config.selectCandidateKeys:find(key, 1, true) or 0) - 1
		if cand_idx >= 0 then
			if state.candidateIndex + cand_idx < #state.candidates then
				state.candidateIndex = state.candidateIndex + cand_idx
				common.kakutei(context)
			end
			return
		end
	end

	common.kakutei(context)
	local notation = require("skkelua.notation")
	require("skkelua.keymap").handle_key(context, notation.key_to_notation[key] or key)
end

--- 接尾辞変換 (">" キー)
---@param context skkelua.Context
function M.suffix(context)
	if context.state.type ~= "henkan" then
		return
	end

	local common = require("skkelua.function.common")
	local input_fn = require("skkelua.function.input")
	common.kakutei(context)
	input_fn.henkan_point(context)
	input_fn.accept_result(context, { ">", "" }, "")
	context.state.affix = "suffix"
end

--- テスト用: 再入フラグをリセットする
function M._reset()
	henkan_locked = false
end

return M
