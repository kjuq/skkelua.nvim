-- Google 日本語入力 API ソース (sources/google_japanese_input.ts に相当)
-- Deno の fetch を curl (vim.system) で置き換えている

local M = {}

-- Note: Google API access may be slow.
local TIMEOUT_MS = 500

--------------------------------------------------------------------
-- Dictionary
--------------------------------------------------------------------

---@class skkelua.GoogleJapaneseInput: skkelua.Dictionary
local Dictionary = {}
Dictionary.__index = Dictionary

function Dictionary.new()
	return setmetatable({}, Dictionary)
end

---@param type_ skkelua.HenkanType
---@param word string
---@return string[]
function Dictionary:get_henkan_result(type_, word)
	-- It should not work for "okuriari".
	if type_ == "okuriari" then
		return {}
	end
	return self:get_midashis(word)
end

---@return skkelua.CompletionData
function Dictionary:get_completion_result(_prefix, _feed)
	-- Note: It does not support completions
	return {}
end

---@private
---@param prefix string
---@return string[]
function Dictionary:get_midashis(prefix)
	local config = require("skkelua.config").config
	if vim.fn.executable("curl") ~= 1 then
		if config.debug then
			vim.print("skkelua: curl is not available")
		end
		return {}
	end
	local url = ("http://www.google.com/transliterate?langpair=%s&text=%s"):format(
		vim.uri_encode("ja-Hira|ja", "rfc2396"),
		vim.uri_encode(prefix .. ",", "rfc2396")
	)
	local ok, result = pcall(function()
		return vim.system(
			{ "curl", "-s", "--max-time", tostring(TIMEOUT_MS / 1000), url },
			{ text = true }
		):wait(TIMEOUT_MS + 200)
	end)
	if not ok or result.code ~= 0 then
		if config.debug and not ok then
			vim.print(result)
		end
		return {}
	end
	local ok_json, resp = pcall(vim.json.decode, result.stdout)
	if not ok_json or type(resp) ~= "table" or type(resp[1]) ~= "table" then
		return {}
	end
	local candidates = resp[1][2]
	if type(candidates) ~= "table" then
		return {}
	end
	return candidates
end

function Dictionary:close() end

M.Dictionary = Dictionary

--------------------------------------------------------------------
-- Source
--------------------------------------------------------------------

---@class skkelua.GoogleJapaneseInputSource
local Source = {}
Source.__index = Source

function Source.new()
	return setmetatable({}, Source)
end

---@return skkelua.Dictionary[]
function Source:get_dictionaries()
	return { Dictionary.new() }
end

M.Source = Source

return M
