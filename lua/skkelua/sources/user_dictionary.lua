-- ユーザー辞書ソース (sources/user_dictionary.ts に相当)

local dictionary = require("skkelua.dictionary")
local util = require("skkelua.util")

local M = {}

local function new_ordered_map()
	return { map = {}, keys = {} }
end

local function omap_set(omap, key, value)
	if omap.map[key] == nil then
		omap.keys[#omap.keys + 1] = key
	end
	omap.map[key] = value
end

local function omap_delete(omap, key)
	if omap.map[key] ~= nil then
		omap.map[key] = nil
		for i, k in ipairs(omap.keys) do
			if k == key then
				table.remove(omap.keys, i)
				break
			end
		end
	end
end

-- FIXME: 一旦送りありエントリブロックを無視する
---@param candidates string[]
---@return string[]
local function filter_blocks(candidates)
	local result = {}
	for _, c in ipairs(candidates) do
		if c:sub(1, 1) ~= "[" then
			result[#result + 1] = c
		end
	end
	return result
end

--- "/" 区切りの候補文字列を [送りブロック] を保持しつつ分割する
--- (JS の matchAll(/\[[^\]]+\]|[^/]+/g) に相当)
---@param s string
---@return string[]
local function match_candidates(s)
	local result = {}
	local pos = 1
	local len = #s
	while pos <= len do
		local matched = false
		if s:sub(pos, pos) == "[" then
			local close = s:find("]", pos + 1, true)
			if close and close > pos + 1 then
				result[#result + 1] = s:sub(pos, close)
				pos = close + 1
				matched = true
			end
		end
		if not matched then
			if s:sub(pos, pos) == "/" then
				pos = pos + 1
			else
				local slash = s:find("/", pos, true)
				local last = (slash or len + 1) - 1
				result[#result + 1] = s:sub(pos, last)
				pos = last + 1
			end
		end
	end
	return result
end

M._match_candidates = match_candidates

--------------------------------------------------------------------
-- Dictionary
--------------------------------------------------------------------

---@class skkelua.UserDictionary: skkelua.Dictionary
local Dictionary = {}
Dictionary.__index = Dictionary

function Dictionary.new()
	local self = setmetatable({}, Dictionary)
	self.okuri_ari = new_ordered_map()
	self.okuri_nasi = new_ordered_map()
	self.rank = new_ordered_map() -- candidate -> number
	self.path = ""
	self.rank_path = ""
	self.load_time = -1
	self.cached_prefix = ""
	self.cached_feed = ""
	self.cached_candidates = {}
	return self
end

---@param type_ skkelua.HenkanType
---@param word string
---@return string[]
function Dictionary:get_henkan_result(type_, word)
	local target = type_ == "okuriari" and self.okuri_ari or self.okuri_nasi
	return filter_blocks(target.map[word] or {})
end

---@private
---@param prefix string
---@param feed string
function Dictionary:cache_candidates(prefix, feed)
	if self.cached_prefix == prefix and self.cached_feed == feed then
		return
	end
	local config = require("skkelua.config").config
	local candidates = {}
	if feed ~= "" then
		local table_ = require("skkelua.kana").get_kana_table(config.kanaTable)
		for _, entry in ipairs(table_) do
			local key, kanas = entry[1], entry[2]
			if util.starts_with(key, feed) and type(kanas) == "table" and #kanas > 1 then
				local feed_prefix = prefix .. kanas[1]
				for _, word in ipairs(self.okuri_nasi.keys) do
					if util.starts_with(word, feed_prefix) then
						candidates[#candidates + 1] = { word, filter_blocks(self.okuri_nasi.map[word]) }
					end
				end
			end
		end
	else
		for _, word in ipairs(self.okuri_nasi.keys) do
			if util.starts_with(word, prefix) then
				candidates[#candidates + 1] = { word, self.okuri_nasi.map[word] }
			end
		end
	end
	self.cached_prefix = prefix
	self.cached_feed = feed
	self.cached_candidates = candidates
end

---@param prefix string
---@param feed string
---@return skkelua.CompletionData
function Dictionary:get_completion_result(prefix, feed)
	self:cache_candidates(prefix, feed)
	return self.cached_candidates
end

---@param prefix string
---@return skkelua.RankData
function Dictionary:get_ranks(prefix)
	local set = {}
	self:cache_candidates(prefix, "")
	for _, entry in ipairs(self.cached_candidates) do
		for _, c in ipairs(entry[2]) do
			set[c] = true
		end
	end
	local result = {}
	for _, candidate in ipairs(self.rank.keys) do
		if set[candidate] then
			result[#result + 1] = { candidate, self.rank.map[candidate] }
		end
	end
	return result
end

---@param type_ skkelua.HenkanType
---@param word string
---@param candidate string
function Dictionary:register_henkan_result(type_, word, candidate)
	if candidate == "" then
		return
	end
	local target = type_ == "okuriari" and self.okuri_ari or self.okuri_nasi
	local old_candidates = target.map[word] or {}
	local new_candidates = { candidate }
	for _, c in ipairs(old_candidates) do
		if c ~= candidate then
			new_candidates[#new_candidates + 1] = c
		end
	end
	omap_set(target, word, new_candidates)
	omap_set(self.rank, candidate, util.now_ms())
	self.cached_prefix = ""
end

---@param type_ skkelua.HenkanType
---@param word string
---@param candidate string
function Dictionary:purge_candidate(type_, word, candidate)
	local target = type_ == "okuriari" and self.okuri_ari or self.okuri_nasi
	local new_candidates = {}
	for _, c in ipairs(target.map[word] or {}) do
		if c ~= candidate then
			new_candidates[#new_candidates + 1] = c
		end
	end
	if #new_candidates > 0 then
		omap_set(target, word, new_candidates)
	else
		omap_delete(target, word)
	end
end

---@private
---@param path string
---@param rank_path string
function Dictionary:read_file(path, rank_path)
	self.okuri_ari = new_ordered_map()
	self.okuri_nasi = new_ordered_map()

	local f = assert(io.open(path, "rb"))
	local data = f:read("*a")
	f:close()

	local mode = nil
	for line in vim.gsplit(data, "\n") do
		if line == dictionary.okuri_ari_marker then
			mode = self.okuri_ari
		elseif line == dictionary.okuri_nasi_marker then
			mode = self.okuri_nasi
		elseif mode then
			local pos = line:find(" ", 1, true)
			if pos then
				omap_set(mode, line:sub(1, pos - 1), match_candidates(line:sub(pos + 1)))
			end
		end
	end

	-- rank
	if rank_path == "" then
		return
	end
	local rf = io.open(rank_path, "rb")
	if not rf then
		return
	end
	local rank_json = rf:read("*a")
	rf:close()
	local ok, rank_data = pcall(vim.json.decode, rank_json)
	if not ok or type(rank_data) ~= "table" then
		error("skkelua: invalid rank file")
	end
	self.rank = new_ordered_map()
	for i, c in ipairs(rank_data) do
		if type(c) ~= "string" then
			error("skkelua: invalid rank file")
		end
		omap_set(self.rank, c, i - 1)
	end
end

---@param opts? { path?: string, rankPath?: string }
function Dictionary:load(opts)
	opts = opts or {}
	local path = opts.path or self.path
	local rank_path = opts.rankPath or self.rank_path
	self.path = path
	self.rank_path = rank_path
	if path ~= "" then
		local stat = vim.uv.fs_stat(path)
		if stat then
			local time = stat.mtime.sec * 1000 + math.floor(stat.mtime.nsec / 1e6)
			if time == self.load_time then
				return
			end
			self.load_time = time
			pcall(self.read_file, self, path, rank_path)
		end
		self.cached_prefix = ""
	end
end

---@private
---@param path string
---@param rank_path string
function Dictionary:write_file(path, rank_path)
	-- dictionary
	-- Note: in SKK dictionary reverses candidates sort order if okuriari
	local okuri_ari_words = vim.deepcopy(self.okuri_ari.keys)
	table.sort(okuri_ari_words, function(a, b)
		return a > b
	end)
	local okuri_nasi_words = vim.deepcopy(self.okuri_nasi.keys)
	table.sort(okuri_nasi_words)

	local lines = { dictionary.okuri_ari_marker }
	for _, word in ipairs(okuri_ari_words) do
		lines[#lines + 1] = ("%s /%s/"):format(word, table.concat(self.okuri_ari.map[word], "/"))
	end
	lines[#lines + 1] = dictionary.okuri_nasi_marker
	for _, word in ipairs(okuri_nasi_words) do
		lines[#lines + 1] = ("%s /%s/"):format(word, table.concat(self.okuri_nasi.map[word], "/"))
	end
	lines[#lines + 1] = ""

	-- デフォルトの保存先 ($XDG_DATA_HOME/nvim/skkelua/) が無い場合に備えて作る
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local f, err = io.open(path, "wb")
	if not f then
		vim.notify(("warning(skkelua): can't write userDictionary to %s"):format(path), vim.log.levels.WARN)
		error(err)
	end
	f:write(table.concat(lines, "\n"))
	f:close()

	-- rank
	if rank_path == "" then
		return
	end
	local entries = {}
	for _, c in ipairs(self.rank.keys) do
		entries[#entries + 1] = { c, self.rank.map[c] }
	end
	table.sort(entries, function(a, b)
		return a[2] < b[2]
	end)
	local rank_list = {}
	for _, e in ipairs(entries) do
		rank_list[#rank_list + 1] = e[1]
	end
	vim.fn.mkdir(vim.fs.dirname(rank_path), "p")
	local rf, rerr = io.open(rank_path, "wb")
	if not rf then
		vim.notify(
			("warning(skkelua): can't write candidate rank data to %s"):format(rank_path),
			vim.log.levels.WARN
		)
		error(rerr)
	end
	rf:write(vim.json.encode(rank_list))
	rf:close()
end

function Dictionary:save()
	local config = require("skkelua.config").config
	if self.path == "" then
		return
	end
	local ok, err = pcall(self.write_file, self, self.path, self.rank_path)
	if not ok then
		if config.debug then
			vim.print(err)
		end
		return
	end
	local stat = vim.uv.fs_stat(self.path)
	self.load_time = stat and (stat.mtime.sec * 1000 + math.floor(stat.mtime.nsec / 1e6)) or -1
end

M.Dictionary = Dictionary

--------------------------------------------------------------------
-- Source
--------------------------------------------------------------------

---@class skkelua.UserDictionarySource
local Source = {}
Source.__index = Source

function Source.new()
	return setmetatable({}, Source)
end

---@return skkelua.Dictionary[]
function Source:get_dictionaries()
	return { self:get_user_dictionary() }
end

---@return skkelua.UserDictionary
function Source:get_user_dictionary()
	local config = require("skkelua.config").config
	local user_dictionary = Dictionary.new()
	local ok, err = pcall(function()
		user_dictionary:load({
			path = config.userDictionary,
			rankPath = config.completionRankFile,
		})
	end)
	if not ok and config.debug then
		vim.print("userDictionary loading failed")
		vim.print(err)
	end
	return user_dictionary
end

M.Source = Source

return M
