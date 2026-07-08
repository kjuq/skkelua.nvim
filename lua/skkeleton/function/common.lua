-- 確定・キャンセルなどの共通機能 (function/common.ts に相当)

local M = {}

--- 現在の状態を確定する
---@param context skkeleton.Context
function M.kakutei(context)
	local state = context.state
	if state.type == "henkan" then
		local candidate = state.candidates[state.candidateIndex + 1]
		local candidate_mod = require("skkeleton.candidate").modify_candidate(candidate, state.affix)
		if candidate then
			local lib = require("skkeleton.store").get_library()
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
		require("skkeleton.function.input").kakutei_feed(context)
		local result = state.henkanFeed .. state.okuriFeed .. state.feed
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
	require("skkeleton.mode").initialize_state_with_abbrev(context, { "converter", "table" })
end

--- 確定キーの処理 (確定する物が無い状態ではひらがなモードに戻す)
--- この動作は ddskk に存在する
---@param context skkeleton.Context
function M.kakutei_key(context)
	local state = context.state
	if state.type == "input" and state.mode == "direct" and state.feed == "" then
		require("skkeleton.function.mode").hirakana(context)
		return
	end
	M.kakutei(context)
end

--- 改行キー
---@param context skkeleton.Context
function M.newline(context)
	local config = require("skkeleton.config").config
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
---@param context skkeleton.Context
function M.cancel(context)
	local config = require("skkeleton.config").config
	local mode = require("skkeleton.mode")
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

--- 候補を辞書から削除する
---@param context skkeleton.Context
function M.purge_candidate(context)
	local state = context.state
	local type_, word, candidate
	if state.type == "input" then
		type_ = context.lastCandidate.type
		word = context.lastCandidate.word
		candidate = context.lastCandidate.candidate
	elseif state.type == "henkan" then
		type_ = state.mode
		word = state.word
		candidate = state.candidates[state.candidateIndex + 1]
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
		local lib = require("skkeleton.store").get_library()
		lib:purge_candidate(type_, word, candidate)
		require("skkeleton.state").initialize_state(state)
		context.lastCandidate.word = ""
	end
end

return M
