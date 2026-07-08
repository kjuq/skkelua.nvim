-- 状態別キーマップ (keymap.ts に相当)


local M = {}

---@class skkelua.KeyMap
---@field default fun(context: skkelua.Context, char: string)|string
---@field map table<string, skkelua.Func|string>

-- Note: 関数は名前 (文字列) で保持し、実行時に function.lua から解決する
-- (モジュールロード順の都合と registerKeyMap との一貫性のため)
local key_maps = {
	input = {
		default = "kanaInput",
		map = {
			["<bs>"] = "deleteChar",
			["<c-g>"] = "cancel",
			["<c-h>"] = "deleteChar",
			["<cr>"] = "newline",
			["<esc>"] = "escape",
			["<nl>"] = "kakutei",
			["<c-q>"] = "hankatakana",
			[">"] = "prefix",
		},
	},
	henkan = {
		default = "henkanInput",
		map = {
			["<c-g>"] = "cancel",
			["<cr>"] = "newline",
			["<nl>"] = "kakutei",
			["<space>"] = "henkanForward",
			["x"] = "henkanBackward",
			["X"] = "purgeCandidate",
			[">"] = "suffix",
		},
	},
}

--- 名前から機能関数を解決する
---@param name string
---@return skkelua.Func
local function resolve(name)
	if name == "kanaInput" then
		return require("skkelua.function.input").kana_input
	end
	local fn = require("skkelua.function").functions()[name]
	if not fn then
		error(("unknown function: %s"):format(name))
	end
	return fn
end

--- キーを処理する
---@param context skkelua.Context
---@param key string notation 形式のキー
function M.handle_key(context, key)
	local config = require("skkelua.config").config
	local notation = require("skkelua.notation")
	local key_map = key_maps[context.state.type]
	if not key_map then
		error("Illegal State: " .. tostring(context.state.type))
	end
	if config.debug then
		vim.print(("handleKey: %s"):format(key))
	end
	local fn = key_map.map[key] or key_map.default
	if type(fn) == "string" then
		fn = resolve(fn)
	end
	fn(context, notation.notation_to_key[key] or key)
end

--- キーマップを登録・削除する (registerKeyMap 相当)
---@param state string "input" | "henkan"
---@param key string notation 形式のキー
---@param func any 関数名。falsy なら削除
function M.register_key_map(state, key, func)
	local config = require("skkelua.config").config
	if config.debug then
		vim.print(("registerKeyMap: state = %s key = %s func = %s"):format(state, key, tostring(func)))
	end
	local key_map = key_maps[state]
	if not key_map then
		error(("unknown state: %s"):format(state))
	end
	if func == nil or func == vim.NIL or func == false or func == "" then
		key_map.map[key] = nil
		return
	end
	local name = tostring(func)
	-- 存在チェック (実際の解決は実行時)
	if not require("skkelua.function").functions()[name] then
		error(("unknown function: %s"):format(name))
	end
	key_map.map[key] = name
end

--- テスト用: 登録されている機能名を返す
---@param state string
---@param key string
---@return string|skkelua.Func|nil
function M._get(state, key)
	local key_map = key_maps[state]
	return key_map and key_map.map[key]
end

return M
