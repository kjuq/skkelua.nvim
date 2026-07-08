-- SKK 形式のグローバル辞書ソース (sources/skk_dictionary.ts に相当)

local dictionary = require("skkelua.dictionary")
local util = require("skkelua.util")

local M = {}

--------------------------------------------------------------------
-- 挿入順を保持する Map (JS の Map 相当)
--------------------------------------------------------------------

local function new_ordered_map()
	return { map = {}, keys = {} }
end

local function omap_set(omap, key, value)
	if omap.map[key] == nil then
		omap.keys[#omap.keys + 1] = key
	end
	omap.map[key] = value
end

M._new_ordered_map = new_ordered_map
M._omap_set = omap_set

--------------------------------------------------------------------
-- Dictionary
--------------------------------------------------------------------

---@class skkelua.SkkDictionary: skkelua.Dictionary
local Dictionary = {}
Dictionary.__index = Dictionary

function Dictionary.new()
	local self = setmetatable({}, Dictionary)
	self.okuri_ari = new_ordered_map()
	self.okuri_nasi = new_ordered_map()
	self.cached_candidates = {}
	return self
end

---@param type_ skkelua.HenkanType
---@param word string
---@return string[]
function Dictionary:get_henkan_result(type_, word)
	local target = type_ == "okuriari" and self.okuri_ari or self.okuri_nasi
	return target.map[word] or {}
end

---@param prefix string
---@param feed string
---@return skkelua.CompletionData
function Dictionary:get_completion_result(prefix, feed)
	local candidates = {}
	if feed ~= "" then
		local table_ = require("skkelua.kana").get_kana_table()
		for _, entry in ipairs(table_) do
			local key, kanas = entry[1], entry[2]
			if util.starts_with(key, feed) and type(kanas) == "table" and #kanas > 1 then
				local feed_prefix = prefix .. kanas[1]
				for _, e in ipairs(self:get_cached_candidates(util.first_char(prefix))) do
					if util.starts_with(e[1], feed_prefix) then
						candidates[#candidates + 1] = e
					end
				end
			end
		end
	else
		for _, e in ipairs(self:get_cached_candidates(util.first_char(prefix))) do
			if util.starts_with(e[1], prefix) then
				candidates[#candidates + 1] = e
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a[1] < b[1]
	end)
	return candidates
end

---@private
---@param prefix string 先頭 1 文字
---@return skkelua.CompletionData
function Dictionary:get_cached_candidates(prefix)
	if self.cached_candidates[prefix] then
		return self.cached_candidates[prefix]
	end
	local candidates = {}
	for _, word in ipairs(self.okuri_nasi.keys) do
		if util.starts_with(word, prefix) then
			candidates[#candidates + 1] = { word, self.okuri_nasi.map[word] }
		end
	end
	self.cached_candidates[prefix] = candidates
	return candidates
end

---@param path string
---@param encoding string
---@return skkelua.SkkDictionary
function Dictionary:load(path, encoding)
	if path:match("%.ya?ml$") then
		error("skkelua: yaml dictionary is not supported by the lua version: " .. path)
	elseif path:match("%.json$") then
		local f = assert(io.open(path, "rb"))
		local data = f:read("*a")
		f:close()
		self:load_json(data)
	elseif path:match("%.mpk$") then
		local f = assert(io.open(path, "rb"))
		local data = f:read("*a")
		f:close()
		self:load_msgpack(data)
	else
		local file = util.read_file_with_encoding(path, encoding)
		self:load_string(file)
	end
	return self
end

--- 構造化辞書 (json/mpk) の中身を検証して取り込む
---@private
---@param jisyo any
function Dictionary:load_structured(jisyo)
	if type(jisyo) ~= "table" or type(jisyo.okuri_ari) ~= "table" or type(jisyo.okuri_nasi) ~= "table" then
		error("skkelua: invalid dictionary: okuri_ari/okuri_nasi are required")
	end
	local function validate_and_build(record)
		local omap = new_ordered_map()
		-- Note: JSON/msgpack のオブジェクトはキー順が保存されないため、
		--       決定的になるようキーをソートして挿入する
		local words = {}
		for word, candidates in pairs(record) do
			if type(word) ~= "string" or type(candidates) ~= "table" then
				error("skkelua: invalid dictionary entry")
			end
			for _, c in ipairs(candidates) do
				if type(c) ~= "string" then
					error("skkelua: invalid dictionary candidate")
				end
			end
			words[#words + 1] = word
		end
		table.sort(words)
		for _, word in ipairs(words) do
			omap_set(omap, word, record[word])
		end
		return omap
	end
	self.okuri_ari = validate_and_build(jisyo.okuri_ari)
	self.okuri_nasi = validate_and_build(jisyo.okuri_nasi)
	self.cached_candidates = {}
end

---@private
---@param data string
function Dictionary:load_json(data)
	local ok, jisyo = pcall(vim.json.decode, data)
	if not ok then
		error("skkelua: failed to parse json dictionary: " .. tostring(jisyo))
	end
	self:load_structured(jisyo)
end

---@private
---@param data string
function Dictionary:load_msgpack(data)
	local ok, jisyo = pcall(vim.mpack.decode, data)
	if not ok then
		error("skkelua: failed to parse msgpack dictionary: " .. tostring(jisyo))
	end
	self:load_structured(jisyo)
end

---@private
---@param data string
function Dictionary:load_string(data)
	self.okuri_ari = new_ordered_map()
	self.okuri_nasi = new_ordered_map()
	self.cached_candidates = {}

	-- Note: SKK-JISYO.L 級 (数十万行) を読むため、vim.gsplit/vim.split ではなく
	--       gmatch ベースの手書きループで処理する
	local mode = nil
	local mode_map, mode_keys
	for line in data:gmatch("[^\n]+") do
		if line:byte(-1) == 13 then -- CRLF
			line = line:sub(1, -2)
		end
		if line == dictionary.okuri_ari_marker then
			mode = self.okuri_ari
			mode_map, mode_keys = mode.map, mode.keys
		elseif line == dictionary.okuri_nasi_marker then
			mode = self.okuri_nasi
			mode_map, mode_keys = mode.map, mode.keys
		elseif mode then
			local pos = line:find(" ", 1, true)
			if pos then
				local word = line:sub(1, pos - 1)
				local body = line:sub(pos + 2, -2)
				local candidates = {}
				for c in body:gmatch("[^/]+") do
					candidates[#candidates + 1] = c
				end
				if mode_map[word] == nil then
					mode_keys[#mode_keys + 1] = word
				end
				mode_map[word] = candidates
			end
		end
	end
end

M.Dictionary = Dictionary

--------------------------------------------------------------------
-- Source
--------------------------------------------------------------------

---@class skkelua.SkkDictionarySource
local Source = {}
Source.__index = Source

function Source.new()
	return setmetatable({}, Source)
end

---@return skkelua.Dictionary[]
function Source:get_dictionaries()
	local config = require("skkelua.config").config
	local dictionaries = {}
	for _, entry in ipairs(config.globalDictionaries) do
		local path, encoding_name = entry[1], entry[2]
		local ok, dict_or_err = pcall(function()
			local dict = Dictionary.new()
			dict:load(path, encoding_name)
			return dict
		end)
		if ok then
			dictionaries[#dictionaries + 1] = dictionary.wrap_dictionary(dict_or_err)
		else
			vim.notify(
				("globalDictionary loading failed\nat %s"):format(path),
				vim.log.levels.ERROR
			)
			if config.debug then
				vim.print(dict_or_err)
			end
		end
	end
	return dictionaries
end

M.Source = Source

return M
