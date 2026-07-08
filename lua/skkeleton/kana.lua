-- かな変換テーブルの管理 (kana.ts に相当)
--
-- KanaTable: { from, result }[] の配列
-- KanaResult: { to, feed } のペア、または機能関数 (function)
-- ビルトインテーブル (kana/rom_hira.lua 等) では機能関数を文字列名で持ち、
-- 初回ロード時に function.lua の関数へ解決する (require 循環の回避のため)

local util = require("skkeleton.util")

local M = {}

---@alias skkeleton.KanaResult [string, string]|skkeleton.Func
---@alias skkeleton.KanaTable [string, skkeleton.KanaResult][]

---@type table<string, skkeleton.KanaTable>?
local tables = nil

local current_kana_table = "rom"

--- 文字列名の機能関数を実関数に解決したテーブルを作る
---@param raw table
---@return skkeleton.KanaTable
local function resolve_table(raw)
	local functions = require("skkeleton.function").functions()
	local resolved = {}
	for _, entry in ipairs(raw) do
		local from, result = entry[1], entry[2]
		if type(result) == "string" then
			local fn = functions[result]
			if not fn then
				error(("function not found: %s"):format(result))
			end
			resolved[#resolved + 1] = { from, fn }
		else
			resolved[#resolved + 1] = { from, result }
		end
	end
	return resolved
end

---@return table<string, skkeleton.KanaTable>
local function get_tables()
	if not tables then
		tables = {
			rom = resolve_table(require("skkeleton.kana.rom_hira")),
			zen = resolve_table(require("skkeleton.kana.rom_zen")),
		}
	end
	return tables
end

--- 現在のかなテーブル名を取得する
---@return string
function M.get_current_kana_table()
	return current_kana_table
end

--- 現在のかなテーブル名を設定する
---@param name string
function M.set_current_kana_table(name)
	current_kana_table = name
end

--- かなテーブルを取得する
---@param name? string 省略時は現在のテーブル
---@return skkeleton.KanaTable
function M.get_kana_table(name)
	name = name or current_kana_table
	local table_ = get_tables()[name]
	if not table_ then
		error(("undefined table: %s"):format(name))
	end
	return table_
end

--- KanaResult へ正規化する。falsy はエントリ削除を表す nil を返す
---@param result any
---@return skkeleton.KanaResult?
local function as_kana_result(result)
	if type(result) == "string" then
		local fn = require("skkeleton.function").functions()[result]
		if not fn then
			error(("function not found: %s"):format(result))
		end
		return fn
	elseif type(result) == "table" and result ~= vim.NIL and #result >= 1 then
		for _, v in ipairs(result) do
			if type(v) ~= "string" then
				error(("Illegal result: %s"):format(vim.inspect(result)))
			end
		end
		return { result[1], result[2] or "" }
	elseif result == nil or result == vim.NIL or result == false or result == "" then
		return nil
	end
	error(("Illegal result: %s"):format(vim.inspect(result)))
end

--- テーブル `name` に部分テーブルをマージする
--- 存在しないテーブルは create=true の時のみ作成する
---@param name string
---@param partial [string, skkeleton.KanaResult?][]
---@param create? boolean
local function inject_kana_table(name, partial, create)
	local t = get_tables()
	if not t[name] and not create then
		error(("table %s is not found."):format(name))
	end
	local merged = {}
	vim.list_extend(merged, partial)
	vim.list_extend(merged, t[name] or {})
	local distinct = util.distinct(merged, function(e)
		return e[1]
	end)
	local filtered = {}
	for _, e in ipairs(distinct) do
		if e[2] ~= nil then
			filtered[#filtered + 1] = e
		end
	end
	table.sort(filtered, function(a, b)
		return a[1] < b[1]
	end)
	t[name] = filtered
end

--- かなテーブルを登録・上書きする (registerKanaTable 相当)
---@param name string
---@param raw_table table<string, any>
---@param create? boolean
function M.register_kana_table(name, raw_table, create)
	local config = require("skkeleton.config").config
	if config.debug then
		vim.print("skkeleton: new kana table")
		vim.print(("name: %s, table: %s"):format(name, vim.inspect(raw_table)))
	end
	if type(raw_table) ~= "table" then
		error("kana table must be a dict")
	end
	local partial = {}
	for kana, result in pairs(raw_table) do
		local lower = kana:lower()
		if kana ~= lower then
			kana = ("<s-%s>"):format(lower)
		end
		-- result が falsy の場合は { kana } となり、既存エントリの削除マーカーとして働く
		partial[#partial + 1] = { kana, as_kana_result(result) }
	end
	inject_kana_table(name, partial, create)
end

--- かなテーブルファイルの中身をパースする
---@param file string
---@return [string, skkeleton.KanaResult][]
local function parse_kana_table_file(file)
	local entries = {}
	for line in vim.gsplit(file, "\n") do
		if not vim.startswith(line, "#") and vim.trim(line) ~= "" then
			local from, result = line:match("^([^,]*),([^,]*)")
			if from then
				entries[#entries + 1] = { from, { result or "", "" } }
			end
		end
	end
	return entries
end

--- 複数のかなテーブルファイルを "rom" にマージする (loadKanaTableFiles 相当)
---@param payload (string|[string, string])[]
function M.load_kana_table_files(payload)
	local entries = {}
	for _, v in ipairs(payload) do
		local path, encoding_name
		if type(v) == "table" then
			path, encoding_name = v[1], v[2]
		else
			path, encoding_name = v, nil
		end
		local file = util.read_file_with_encoding(path, encoding_name)
		vim.list_extend(entries, parse_kana_table_file(file))
	end
	inject_kana_table("rom", entries)
end

--- かなテーブルファイルを指定テーブルにロードする (loadKanaTableFile 相当)
---@param table_name string
---@param path string
---@param encoding string
---@param create? boolean
function M.load_kana_table_file(table_name, path, encoding, create)
	local file = util.read_file_with_encoding(path, encoding)
	inject_kana_table(table_name, parse_kana_table_file(file), create)
end

--- テスト用: テーブル状態をリセットする
function M._reset()
	tables = nil
	current_kana_table = "rom"
end

return M
