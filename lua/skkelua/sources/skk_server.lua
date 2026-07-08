-- skkserv プロトコルの辞書ソース (sources/skk_server.ts に相当)
-- Deno の非同期 TCP を vim.uv + vim.wait による同期待ちで置き換えている

local util = require("skkelua.util")

local M = {}

-- 応答待ちのタイムアウト (ms)
local RESPONSE_TIMEOUT = 1000

--------------------------------------------------------------------
-- Dictionary
--------------------------------------------------------------------

---@class skkelua.SkkServer: skkelua.Dictionary
local Dictionary = {}
Dictionary.__index = Dictionary

---@param opts { hostname: string, port: number, requestEnc: string, responseEnc: string }
function Dictionary.new(opts)
	local self = setmetatable({}, Dictionary)
	self.request_encoding = util.normalize_encoding(opts.requestEnc) or "euc-jp"
	self.response_encoding = util.normalize_encoding(opts.responseEnc) or "euc-jp"
	self.hostname = opts.hostname
	self.port = opts.port
	self.conn = nil
	return self
end

---@param close? boolean
function Dictionary:connect(close)
	if close then
		self:close()
	end
	if self.conn then
		return
	end

	-- ホスト名を解決する (tcp_connect は IP アドレスしか受け付けない)
	local addrinfo = vim.uv.getaddrinfo(self.hostname, nil, {
		family = "inet",
		socktype = "stream",
	})
	local addr = addrinfo and addrinfo[1] and addrinfo[1].addr
	if not addr then
		error(("skkelua: can't resolve host: %s"):format(self.hostname))
	end

	local tcp = assert(vim.uv.new_tcp())
	local connect_result = nil
	tcp:connect(addr, self.port, function(err)
		connect_result = err or "ok"
	end)
	vim.wait(RESPONSE_TIMEOUT, function()
		return connect_result ~= nil
	end, 5)
	if connect_result ~= "ok" then
		tcp:close()
		error(("skkelua: can't connect to skk server %s:%d (%s)"):format(
			self.hostname,
			self.port,
			tostring(connect_result)
		))
	end

	local conn = { tcp = tcp, buffer = "", lines = {} }
	self.conn = conn
	tcp:read_start(function(err, chunk)
		if err or chunk == nil then
			-- 切断
			if not tcp:is_closing() then
				tcp:close()
			end
			if self.conn == conn then
				self.conn = nil
			end
			return
		end
		conn.buffer = conn.buffer .. chunk
		while true do
			local pos = conn.buffer:find("\n", 1, true)
			if not pos then
				break
			end
			local line = conn.buffer:sub(1, pos - 1)
			conn.buffer = conn.buffer:sub(pos + 1)
			conn.lines[#conn.lines + 1] = line
		end
	end)
end

--- リクエストを送り 1 行の応答を待つ
---@private
---@param request string
---@return string? UTF-8 に変換済みの応答行
function Dictionary:request_line(request)
	local ok = pcall(self.connect, self)
	if not ok or not self.conn then
		return nil
	end
	local conn = self.conn
	conn.lines = {}
	self:write(request)
	local got = vim.wait(RESPONSE_TIMEOUT, function()
		return #conn.lines > 0
	end, 5)
	if not got then
		return nil
	end
	local line = table.remove(conn.lines, 1)
	local ok_decode, decoded = pcall(util.decode, line, self.response_encoding)
	return ok_decode and decoded or nil
end

---@param type_ skkelua.HenkanType
---@param word string
---@return string[]
function Dictionary:get_henkan_result(type_, word)
	local _ = type_
	local response = self:request_line("1" .. word .. " ")
	if not response or response:sub(1, 1) ~= "1" then
		return {}
	end
	-- "1/候補1/候補2/" -> { "候補1", "候補2" }
	local parts = vim.split(response, "/", { plain = true })
	-- 先頭 ("1") と末尾 (空文字) を除く
	local result = {}
	for i = 2, #parts - 1 do
		result[#result + 1] = parts[i]
	end
	return result
end

---@param prefix string
---@param feed string
---@return skkelua.CompletionData
function Dictionary:get_completion_result(prefix, feed)
	local midashis = {}
	if feed ~= "" then
		local table_ = require("skkelua.kana").get_kana_table()
		for _, entry in ipairs(table_) do
			local key, kanas = entry[1], entry[2]
			if util.starts_with(key, feed) and type(kanas) == "table" and #kanas > 1 then
				local feed_prefix = prefix .. kanas[1]
				vim.list_extend(midashis, self:get_midashis(feed_prefix))
			end
		end
	else
		midashis = self:get_midashis(prefix)
	end

	local candidates = {}
	for _, midashi in ipairs(midashis) do
		candidates[#candidates + 1] = { midashi, self:get_henkan_result("okurinasi", midashi) }
	end
	return candidates
end

--- 見出し語の補完 (プロトコル 4)
---@private
---@param prefix string
---@return string[]
function Dictionary:get_midashis(prefix)
	local response = self:request_line("4" .. prefix .. " ")
	if not response or response:sub(1, 1) ~= "1" then
		return {}
	end
	-- "/" と空白で分割し、先頭と末尾を除く
	local parts = vim.split(response, "[/%s]")
	local result = {}
	for i = 2, #parts - 1 do
		result[#result + 1] = parts[i]
	end
	return result
end

function Dictionary:close()
	pcall(function()
		self:write("0")
	end)
	if self.conn then
		if not self.conn.tcp:is_closing() then
			self.conn.tcp:close()
		end
		self.conn = nil
	end
end

---@private
---@param str string
function Dictionary:write(str)
	if not self.conn then
		return
	end
	self.conn.tcp:write(util.encode(str, self.request_encoding))
end

M.Dictionary = Dictionary

--------------------------------------------------------------------
-- Source
--------------------------------------------------------------------

---@class skkelua.SkkServerSource
local Source = {}
Source.__index = Source

function Source.new()
	return setmetatable({}, Source)
end

---@return skkelua.Dictionary[]
function Source:get_dictionaries()
	local config = require("skkelua.config").config
	local skk_server = Dictionary.new({
		hostname = config.skkServerHost,
		port = config.skkServerPort,
		requestEnc = config.skkServerReqEnc,
		responseEnc = config.skkServerResEnc,
	})

	local ok, err = pcall(skk_server.connect, skk_server)
	if not ok and config.debug then
		vim.print("connecting to skk server is failed")
		vim.print(err)
	end

	return { skk_server }
end

M.Source = Source

return M
