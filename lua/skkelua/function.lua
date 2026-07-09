-- 機能関数の集約 (function.ts に相当)

local M = {}

---@alias skkelua.Func fun(context: skkelua.Context, char: string)

---@type table<string, skkelua.Func>?
local functions_cache = nil
---@type table<string, skkelua.Func>?
local mode_functions_cache = nil

--- モード切り替え関数のテーブル (modeFunctions 相当)
---@return table<string, skkelua.Func>
function M.mode_functions()
	if not mode_functions_cache then
		local mode = require("skkelua.function.mode")
		mode_functions_cache = {
			abbrev = mode.abbrev,
			hankata = mode.hankatakana,
			hira = mode.hirakana,
			kata = mode.katakana,
			zenkaku = mode.zenkaku,
		}
	end
	return mode_functions_cache
end

--- 全機能関数のテーブル (functions 相当)
---@return table<string, skkelua.Func>
function M.functions()
	if not functions_cache then
		local common = require("skkelua.function.common")
		local disable = require("skkelua.function.disable")
		local henkan = require("skkelua.function.henkan")
		local input = require("skkelua.function.input")
		local mode = require("skkelua.function.mode")
		functions_cache = {
			-- common
			kakutei = common.kakutei_key,
			newline = common.newline,
			cancel = common.cancel,
			purgeCandidate = common.purge_candidate,
			-- disable
			disable = disable.disable,
			escape = disable.escape,
			-- henkan
			henkanFirst = henkan.henkan_first,
			henkanForward = henkan.henkan_forward,
			henkanBackward = henkan.henkan_backward,
			henkanInput = henkan.henkan_input,
			registerWord = henkan.register_word_first,
			suffix = henkan.suffix,
			-- input
			kakuteiFeed = input.kakutei_feed,
			henkanPoint = input.henkan_point,
			deleteChar = input.delete_char,
			prefix = input.prefix,
			-- mode
			abbrev = mode.abbrev,
			hirakana = mode.hirakana,
			katakana = mode.katakana,
			hankatakana = mode.hankatakana,
			zenkaku = mode.zenkaku,
		}
	end
	return functions_cache
end

return M
