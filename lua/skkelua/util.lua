-- ポータビリティ層・文字列ユーティリティ
-- (denops 版 util.ts の Cell/LazyCell はモジュールローカル変数で代替するため存在しない)

local M = {}

-- UTF-8 1 文字にマッチする Lua パターン
local CHAR_PAT = "[%z\1-\127\194-\244][\128-\191]*"

--- 文字列をコードポイント単位の配列に分解する
---@param s string
---@return string[]
function M.chars(s)
	local t = {}
	for c in s:gmatch(CHAR_PAT) do
		t[#t + 1] = c
	end
	return t
end

--- コードポイント数を返す
---@param s string
---@return integer
function M.char_len(s)
	local n = 0
	for _ in s:gmatch(CHAR_PAT) do
		n = n + 1
	end
	return n
end

--- 文字単位の substring (string.sub と同じく i, j は inclusive、負数は末尾から)
---@param s string
---@param i integer
---@param j? integer
---@return string
function M.char_sub(s, i, j)
	local cs = M.chars(s)
	local n = #cs
	j = j or -1
	if i < 0 then
		i = n + i + 1
	end
	if j < 0 then
		j = n + j + 1
	end
	if i < 1 then
		i = 1
	end
	if j > n then
		j = n
	end
	if i > j then
		return ""
	end
	return table.concat(cs, "", i, j)
end

--- 先頭 1 文字を返す (str[0] 相当)
---@param s string
---@return string
function M.first_char(s)
	return s:match(CHAR_PAT) or ""
end

--- s が prefix で始まるか (バイト単位で判定して良い; UTF-8 は自己同期符号のため)
---@param s string
---@param prefix string
---@return boolean
function M.starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

--- s が suffix で終わるか
---@param s string
---@param suffix string
---@return boolean
function M.ends_with(s, suffix)
	return suffix == "" or s:sub(-#suffix) == suffix
end

--- "~" 始まりのパスをホームディレクトリに展開する
---@param path string
---@return string
function M.home_expand(path)
	if path:sub(1, 1) == "~" then
		local home = vim.uv.os_homedir() or ""
		return home .. path:sub(2)
	end
	return path
end

-- 簡易エンコーディング判定 (encoding-japanese の detect 相当の縮小版)
-- SKK 辞書で実用されるのは euc-jp / utf-8 / sjis 程度なのでそれだけ判定する

---@param data string
---@return boolean
local function is_valid_utf8(data)
	local i = 1
	local len = #data
	local byte = string.byte
	while i <= len do
		local c = byte(data, i)
		if c < 0x80 then
			i = i + 1
		elseif c >= 0xC2 and c <= 0xDF then
			local c2 = byte(data, i + 1)
			if not c2 or c2 < 0x80 or c2 > 0xBF then
				return false
			end
			i = i + 2
		elseif c >= 0xE0 and c <= 0xEF then
			local c2, c3 = byte(data, i + 1), byte(data, i + 2)
			if not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then
				return false
			end
			i = i + 3
		elseif c >= 0xF0 and c <= 0xF4 then
			local c2, c3, c4 = byte(data, i + 1), byte(data, i + 2), byte(data, i + 3)
			if not c4 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF or c4 < 0x80 or c4 > 0xBF then
				return false
			end
			i = i + 4
		else
			return false
		end
	end
	return true
end

---@param data string
---@return boolean
local function is_valid_eucjp(data)
	local i = 1
	local len = #data
	local byte = string.byte
	while i <= len do
		local c = byte(data, i)
		if c < 0x80 then
			i = i + 1
		elseif c == 0x8E then -- 半角カナ
			local c2 = byte(data, i + 1)
			if not c2 or c2 < 0xA1 or c2 > 0xDF then
				return false
			end
			i = i + 2
		elseif c == 0x8F then -- 補助漢字
			local c2, c3 = byte(data, i + 1), byte(data, i + 2)
			if not c3 or c2 < 0xA1 or c2 > 0xFE or c3 < 0xA1 or c3 > 0xFE then
				return false
			end
			i = i + 3
		elseif c >= 0xA1 and c <= 0xFE then
			local c2 = byte(data, i + 1)
			if not c2 or c2 < 0xA1 or c2 > 0xFE then
				return false
			end
			i = i + 2
		else
			return false
		end
	end
	return true
end

--- エンコーディングを推定して iconv の from-encoding 名を返す
---@param data string
---@return string
function M.detect_encoding(data)
	if data:sub(1, 3) == "\239\187\191" then
		return "utf-8"
	end
	if is_valid_utf8(data) then
		return "utf-8"
	end
	if is_valid_eucjp(data) then
		return "euc-jp"
	end
	return "cp932"
end

-- Encoding 名の正規化テーブル (types.ts の Encode に相当)
-- vim.iconv が解釈できる名前に寄せる
local ENCODING_ALIAS = {
	["euc-jp"] = "euc-jp",
	["eucjp"] = "euc-jp",
	["sjis"] = "cp932",
	["shift-jis"] = "cp932",
	["shift_jis"] = "cp932",
	["cp932"] = "cp932",
	["utf-8"] = "utf-8",
	["utf8"] = "utf-8",
	["utf-16"] = "utf-16",
	["utf-16le"] = "utf-16le",
	["utf-16be"] = "utf-16be",
	["jis"] = "iso-2022-jp",
	["ascii"] = "utf-8", -- ASCII は UTF-8 の部分集合
	["latin1"] = "latin1",
}

--- Encoding 名を vim.iconv 用に正規化する。不明なら nil
---@param name string
---@return string?
function M.normalize_encoding(name)
	return ENCODING_ALIAS[name:lower()]
end

--- エンコーディングを変換して UTF-8 文字列を返す
---@param data string
---@param from string 変換元エンコーディング (iconv 名)
---@return string
function M.decode(data, from)
	if from == "utf-8" then
		return data
	end
	local converted = vim.iconv(data, from, "utf-8")
	if not converted then
		error(("skkelua: iconv failed (from=%s)"):format(from))
	end
	return converted
end

--- UTF-8 文字列を指定エンコーディングに変換する
---@param data string
---@param to string 変換先エンコーディング (iconv 名)
---@return string
function M.encode(data, to)
	if to == "utf-8" then
		return data
	end
	local converted = vim.iconv(data, "utf-8", to)
	if not converted then
		error(("skkelua: iconv failed (to=%s)"):format(to))
	end
	return converted
end

--- ファイルを読み込み UTF-8 文字列として返す (util.ts readFileWithEncoding 相当)
---@param path string
---@param encoding_name? string 空文字や nil なら自動判定
---@return string
function M.read_file_with_encoding(path, encoding_name)
	local f, err = io.open(path, "rb")
	if not f then
		error(("skkelua: can't open file: %s (%s)"):format(path, err))
	end
	local data = f:read("*a")
	f:close()

	local enc
	if encoding_name and encoding_name ~= "" then
		enc = M.normalize_encoding(encoding_name) or encoding_name
	else
		enc = M.detect_encoding(data)
	end
	return M.decode(data, enc)
end

--- 現在時刻をミリ秒で返す (Date.now() 相当)
---@return number
function M.now_ms()
	local sec, usec = vim.uv.gettimeofday()
	return sec * 1000 + math.floor(usec / 1000)
end

--- 配列から重複を除いた新しい配列を返す (先勝ち)
---@generic T
---@param arr T[]
---@param key_fn? fun(x: T): any
---@return T[]
function M.distinct(arr, key_fn)
	local seen = {}
	local result = {}
	for _, v in ipairs(arr) do
		local k = key_fn and key_fn(v) or v
		if not seen[k] then
			seen[k] = true
			result[#result + 1] = v
		end
	end
	return result
end

return M
