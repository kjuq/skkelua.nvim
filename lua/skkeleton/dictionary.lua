-- 辞書ライブラリと数値変換 (dictionary.ts に相当)

local M = {}

M.okuri_ari_marker = ";; okuri-ari entries."
M.okuri_nasi_marker = ";; okuri-nasi entries."

---@alias skkeleton.HenkanType "okuriari"|"okurinasi"
---@alias skkeleton.CompletionData [string, string[]][]
---@alias skkeleton.RankData [string, number][]

--------------------------------------------------------------------
-- 数値変換
--------------------------------------------------------------------

local zenkaku_numbers = { "０", "１", "２", "３", "４", "５", "６", "７", "８", "９" }
local kanji_numbers = { "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }

---@param n integer
---@return string
local function to_zenkaku(n)
	return (tostring(n):gsub("%d", function(c)
		return zenkaku_numbers[tonumber(c) + 1]
	end))
end

---@param n integer
---@return string
local function to_kanji_modern(n)
	return (tostring(n):gsub("%d", function(c)
		return kanji_numbers[tonumber(c) + 1]
	end))
end

-- 将棋の棋譜形式 (76 -> ７六)
---@param n integer
---@return string
local function to_kifu(n)
	local x = math.floor(n / 10)
	local y = n % 10
	if 0 < x and x < 10 and 0 < y and y < 10 then
		return to_zenkaku(x) .. to_kanji_modern(y)
	else
		return tostring(n)
	end
end

-- 位取りの漢数字 (1234 -> 千二百三十四)
---@param n integer
---@return string
local function to_kanji_classic(n)
	if n == 0 then
		return "〇"
	end
	local digits = { "", "十", "百", "千" }
	local units = { "", "万", "億", "兆", "京" }
	local result = {}
	local unit_idx = 1
	while n > 0 do
		local block = n % 10000
		n = math.floor(n / 10000)
		if block > 0 then
			local block_str = {}
			local d = 1
			while block > 0 do
				local v = block % 10
				block = math.floor(block / 10)
				if v > 0 then
					local num = (v == 1 and d > 1) and "" or kanji_numbers[v + 1]
					table.insert(block_str, 1, num .. digits[d])
				end
				d = d + 1
			end
			table.insert(result, 1, table.concat(block_str) .. units[unit_idx])
		end
		unit_idx = unit_idx + 1
	end
	return table.concat(result)
end

-- 大字 (1234 -> 阡弐佰参拾肆)
---@param n integer
---@return string
local function to_daiji(n)
	local daiji_map = {
		["一"] = "壱",
		["二"] = "弐",
		["三"] = "参",
		["四"] = "肆",
		["五"] = "伍",
		["六"] = "陸",
		["七"] = "漆",
		["八"] = "捌",
		["九"] = "玖",
		["〇"] = "零",
		["十"] = "拾",
		["百"] = "佰",
		["千"] = "阡",
		["万"] = "萬",
	}
	local util = require("skkeleton.util")
	local result = {}
	for _, c in ipairs(util.chars(to_kanji_classic(n))) do
		result[#result + 1] = daiji_map[c] or c
	end
	return table.concat(result)
end

-- ローマ数字
---@param n integer
---@return string
local function to_roman(n)
	if n <= 0 then
		return tostring(n)
	end
	local numerals = {
		{ 1000, "M" },
		{ 900, "CM" },
		{ 500, "D" },
		{ 400, "CD" },
		{ 100, "C" },
		{ 90, "XC" },
		{ 50, "L" },
		{ 40, "XL" },
		{ 10, "X" },
		{ 9, "IX" },
		{ 5, "V" },
		{ 4, "IV" },
		{ 1, "I" },
	}
	local result = {}
	for _, pair in ipairs(numerals) do
		while n >= pair[1] do
			result[#result + 1] = pair[2]
			n = n - pair[1]
		end
	end
	return table.concat(result)
end

--- 文字列 s をパターンにマッチした部分も含めて交互に分割する
--- (JS の String.prototype.split の capture group 付き版に相当)
---@param s string
---@param pat string Lua パターン
---@return string[]
local function split_keep(s, pat)
	local result = {}
	local pos = 1
	while true do
		local s1, e1 = s:find(pat, pos)
		if not s1 or e1 < s1 then
			result[#result + 1] = s:sub(pos)
			break
		end
		result[#result + 1] = s:sub(pos, s1 - 1)
		result[#result + 1] = s:sub(s1, e1)
		pos = e1 + 1
	end
	return result
end

--- 数値変換パターン (#0〜#9) を entry の数値で展開する
---@param pattern string 辞書の候補 (例 "#1月#1日")
---@param entry string 入力された見出し (例 "12月25日")
---@return string
local function convert_number(pattern, entry)
	local ps = split_keep(pattern, "#%d?")
	local es = split_keep(entry, "%d+")
	local n = math.min(#ps, #es)
	local result = {}
	for i = 1, n do
		local k, e = ps[i], es[i]
		if k == "#" or k == "#0" or k == "#4" or k == "#6" or k == "#7" then
			result[#result + 1] = e
		elseif k == "#9" then
			result[#result + 1] = to_kifu(tonumber(e) or 0)
		elseif k == "#1" then
			result[#result + 1] = to_zenkaku(tonumber(e) or 0)
		elseif k == "#2" then
			result[#result + 1] = to_kanji_modern(tonumber(e) or 0)
		elseif k == "#3" then
			result[#result + 1] = to_kanji_classic(tonumber(e) or 0)
		elseif k == "#8" then
			result[#result + 1] = to_roman(tonumber(e) or 0)
		elseif k == "#5" then
			result[#result + 1] = to_daiji(tonumber(e) or 0)
		else
			result[#result + 1] = k
		end
	end
	return table.concat(result)
end

M._convert_number = convert_number

--------------------------------------------------------------------
-- 順序付き収集ヘルパー
--------------------------------------------------------------------

--- JS の Map/Set と同じ挿入順を保つ集合に候補を集める
---@param collector { keys: string[], sets: table<string, {list: string[], seen: table<string, boolean>}> }
---@param candidates skkeleton.CompletionData
local function gather_candidates(collector, candidates)
	for _, entry in ipairs(candidates) do
		local kana, cs = entry[1], entry[2]
		local set = collector.sets[kana]
		if not set then
			set = { list = {}, seen = {} }
			collector.sets[kana] = set
			collector.keys[#collector.keys + 1] = kana
		end
		for _, c in ipairs(cs) do
			if not set.seen[c] then
				set.seen[c] = true
				set.list[#set.list + 1] = c
			end
		end
	end
end

--------------------------------------------------------------------
-- NumberConvertWrapper
--------------------------------------------------------------------

---@class skkeleton.Dictionary
---@field get_henkan_result fun(self, type: skkeleton.HenkanType, word: string): string[]
---@field get_completion_result fun(self, prefix: string, feed: string): skkeleton.CompletionData

---@class skkeleton.NumberConvertWrapper: skkeleton.Dictionary
---@field private inner skkeleton.Dictionary
local NumberConvertWrapper = {}
NumberConvertWrapper.__index = NumberConvertWrapper

---@param dict skkeleton.Dictionary
function NumberConvertWrapper.new(dict)
	return setmetatable({ inner = dict }, NumberConvertWrapper)
end

function NumberConvertWrapper:get_henkan_result(type_, word)
	local real_word = word:gsub("%d+", "#")
	local candidates = self.inner:get_henkan_result(type_, real_word)
	if word == real_word then
		return candidates
	end
	local result = {}
	vim.list_extend(result, self.inner:get_henkan_result(type_, word))
	vim.list_extend(result, candidates)
	for i, c in ipairs(result) do
		result[i] = convert_number(c, word)
	end
	return result
end

function NumberConvertWrapper:get_completion_result(prefix, feed)
	local real_prefix = prefix:gsub("%d+", "#")
	local candidates = self.inner:get_completion_result(real_prefix, feed)
	if prefix == real_prefix then
		return candidates
	end
	local result = {}
	vim.list_extend(result, self.inner:get_completion_result(prefix, feed))
	vim.list_extend(result, candidates)
	for i, entry in ipairs(result) do
		local converted = {}
		for _, c in ipairs(entry[2]) do
			converted[#converted + 1] = convert_number(c, prefix)
		end
		result[i] = { entry[1], converted }
	end
	return result
end

M.NumberConvertWrapper = NumberConvertWrapper

--- 数値変換ラッパーを被せる
---@param dict skkeleton.Dictionary
---@return skkeleton.Dictionary
function M.wrap_dictionary(dict)
	return NumberConvertWrapper.new(dict)
end

--------------------------------------------------------------------
-- Library
--------------------------------------------------------------------

---@class skkeleton.Library
---@field private dictionaries skkeleton.Dictionary[]
---@field private user_dictionary? skkeleton.UserDictionary
local Library = {}
Library.__index = Library

---@param dictionaries? skkeleton.Dictionary[]
---@param user_dictionary? skkeleton.UserDictionary
function Library.new(dictionaries, user_dictionary)
	local self = setmetatable({}, Library)
	self.user_dictionary = user_dictionary
	self.dictionaries = {}
	if user_dictionary then
		self.dictionaries = { M.wrap_dictionary(user_dictionary) }
	end
	vim.list_extend(self.dictionaries, dictionaries or {})
	return self
end

---@param type_ skkeleton.HenkanType
---@param word string
---@return string[]
function Library:get_henkan_result(type_, word)
	local config = require("skkeleton.config").config
	if config.immediatelyDictionaryRW then
		self:load()
	end
	local merged = {}
	local seen = {}
	for _, dic in ipairs(self.dictionaries) do
		for _, c in ipairs(dic:get_henkan_result(type_, word)) do
			if not seen[c] then
				seen[c] = true
				merged[#merged + 1] = c
			end
		end
	end
	return merged
end

---@param prefix string
---@param feed string
---@return skkeleton.CompletionData
function Library:get_completion_result(prefix, feed)
	local config = require("skkeleton.config").config
	if config.immediatelyDictionaryRW then
		self:load()
	end
	local collector = { keys = {}, sets = {} }
	if #prefix == 0 then
		return {}
	elseif require("skkeleton.util").char_len(prefix) == 1 then
		for _, dic in ipairs(self.dictionaries) do
			gather_candidates(collector, { { prefix, dic:get_henkan_result("okurinasi", prefix) } })
		end
	else
		for _, dic in ipairs(self.dictionaries) do
			gather_candidates(collector, dic:get_completion_result(prefix, feed))
		end
	end
	local result = {}
	for _, kana in ipairs(collector.keys) do
		result[#result + 1] = { kana, collector.sets[kana].list }
	end
	return result
end

---@param prefix string
---@return skkeleton.RankData
function Library:get_ranks(prefix)
	if not self.user_dictionary then
		return {}
	end
	return self.user_dictionary:get_ranks(prefix)
end

---@param type_ skkeleton.HenkanType
---@param word string
---@param candidate string
function Library:register_henkan_result(type_, word, candidate)
	local config = require("skkeleton.config").config
	if not self.user_dictionary then
		return
	end
	self.user_dictionary:register_henkan_result(type_, word, candidate)
	if config.immediatelyDictionaryRW then
		self.user_dictionary:save()
	end
end

---@param type_ skkeleton.HenkanType
---@param word string
---@param candidate string
function Library:purge_candidate(type_, word, candidate)
	local config = require("skkeleton.config").config
	if not self.user_dictionary then
		return
	end
	self.user_dictionary:purge_candidate(type_, word, candidate)
	if config.immediatelyDictionaryRW then
		self.user_dictionary:save()
	end
end

function Library:load()
	if not self.user_dictionary then
		return
	end
	self.user_dictionary:load({})
end

function Library:save()
	if not self.user_dictionary then
		return
	end
	self.user_dictionary:save()
end

M.Library = Library

--------------------------------------------------------------------
-- ソースのロード
--------------------------------------------------------------------

--- 設定された sources から Library を構築する (load 相当)
---@param sources string[]
---@return skkeleton.Library
function M.load(sources)
	local config = require("skkeleton.config").config
	local user_source = require("skkeleton.sources.user_dictionary").Source.new()
	local user_dictionary = user_source:get_user_dictionary()

	local dictionaries = {}
	for _, source in ipairs(sources) do
		local ok, mod = pcall(require, "skkeleton.sources." .. source)
		if ok and mod.Source then
			local ok2, dicts = pcall(function()
				return mod.Source.new():get_dictionaries()
			end)
			if ok2 then
				vim.list_extend(dictionaries, dicts)
			else
				vim.notify(("skkeleton: failed to load source: %s"):format(source), vim.log.levels.ERROR)
				if config.debug then
					vim.print(dicts)
				end
			end
		else
			vim.notify(("Invalid source name: %s"):format(source), vim.log.levels.ERROR)
			if config.debug then
				vim.print(mod)
			end
		end
	end

	return Library.new(dictionaries, user_dictionary)
end

return M
