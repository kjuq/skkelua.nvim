-- モード切り替え機能 (function/mode.ts に相当)

local M = {}

--- abbrev モードへ移行する
---@param context skkelua.Context
function M.abbrev(context)
	if context.state.type ~= "input" or context.state.mode ~= "direct" then
		return
	end
	local input_fn = require("skkelua.function.input")
	local henkan_first = require("skkelua.function.henkan").henkan_first
	input_fn.henkan_point(context)
	local s = context.state
	local filtered = {}
	for _, e in ipairs(s.table) do
		if e[2] == henkan_first then
			filtered[#filtered + 1] = e
		end
	end
	s.table = filtered
	s.directInput = true
	require("skkelua.mode").mode_change(context, "abbrev")
end

--- ひらがなモードへ移行する
---@param context skkelua.Context
function M.hirakana(context)
	if context.state.type ~= "input" then
		return
	end
	local config = require("skkelua.config").config
	local kana = require("skkelua.kana")
	local state_mod = require("skkelua.state")
	local state = context.state
	if state.mode ~= "direct" then
		require("skkelua.function.common").kakutei(context)
	end
	kana.set_current_kana_table(config.kanaTable)
	if state.type == "input" then
		state.converter = nil
	end
	state_mod.initialize_state(state, { "converter" })
	require("skkelua.mode").mode_change(context, "hira")
end

--- カタカナモードへ移行する (または変換部分をカタカナ化する)
---@param context skkelua.Context
function M.katakana(context)
	if context.state.type ~= "input" then
		return
	end
	local config = require("skkelua.config").config
	local hira_to_kata = require("skkelua.kana.hira_kata").hira_to_kata
	local mode_mod = require("skkelua.mode")
	local state_mod = require("skkelua.state")
	local state = context.state
	if state.mode == "direct" then
		if state.converter then
			state.converter = nil
			mode_mod.mode_change(context, "hira")
		else
			state.converter = hira_to_kata
			mode_mod.mode_change(context, "kata")
		end
		return
	end
	require("skkelua.function.input").kakutei_feed(context)
	local kana = state.henkanFeed .. state.okuriFeed
	local result = kana
	if not state.converter then
		result = hira_to_kata(result)
		if config.registerConvertResult then
			local lib = require("skkelua.store").get_library()
			lib:register_henkan_result("okurinasi", kana, result)
			context.lastCandidate = {
				type = "okurinasi",
				word = kana,
				candidate = result,
			}
		end
	end
	context:kakutei_with_undo_point(result)
	state_mod.initialize_state(state, { "converter" })
end

--- 半角カタカナモードへ移行する (または変換部分を半角カタカナ化する)
---@param context skkelua.Context
function M.hankatakana(context)
	if context.state.type ~= "input" then
		return
	end
	local config = require("skkelua.config").config
	local kana_mod = require("skkelua.kana")
	local hira_to_hankata = require("skkelua.kana.hira_hankata").hira_to_hankata
	local mode_mod = require("skkelua.mode")
	local state_mod = require("skkelua.state")
	local state = context.state
	if state.mode == "direct" then
		if state.converter == hira_to_hankata then
			state.converter = nil
			mode_mod.mode_change(context, "hira")
		else
			if kana_mod.get_current_kana_table() == "zen" then
				kana_mod.set_current_kana_table(config.kanaTable)
				state.table = kana_mod.get_kana_table()
			end
			state.converter = hira_to_hankata
			mode_mod.mode_change(context, "hankata")
		end
		return
	end
	require("skkelua.function.input").kakutei_feed(context)
	local kana = state.henkanFeed .. state.okuriFeed
	local result = kana
	if state.converter ~= hira_to_hankata then
		result = hira_to_hankata(result)
		if config.registerConvertResult then
			local lib = require("skkelua.store").get_library()
			lib:register_henkan_result("okurinasi", kana, result)
			context.lastCandidate = {
				type = "okurinasi",
				word = kana,
				candidate = result,
			}
		end
	end
	context:kakutei_with_undo_point(result)
	state_mod.initialize_state(state, { "converter" })
end

--- 全角英数モードへ移行する
---@param context skkelua.Context
function M.zenkaku(context)
	if context.state.type ~= "input" then
		return
	end
	local kana_mod = require("skkelua.kana")
	local state = context.state
	if state.mode ~= "direct" then
		require("skkelua.function.common").kakutei(context)
	end
	kana_mod.set_current_kana_table("zen")
	state.table = kana_mod.get_kana_table()
	require("skkelua.mode").mode_change(context, "zenkaku")
end

return M
