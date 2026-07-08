-- util.lua のテスト (Lua 版固有の文字列処理・エンコーディング判定)

local t = require("tests.helper")
local util = require("skkelua.util")

t.test("chars / char_len", function()
	t.assert_equals({ "a", "b" }, util.chars("ab"))
	t.assert_equals({ "あ", "い", "う" }, util.chars("あいう"))
	t.assert_equals(3, util.char_len("あいう"))
	t.assert_equals(0, util.char_len(""))
end)

t.test("char_sub", function()
	t.assert_equals("あい", util.char_sub("あいう", 1, -2))
	t.assert_equals("う", util.char_sub("あいう", -1))
	t.assert_equals("bc", util.char_sub("abc", 2))
	t.assert_equals("", util.char_sub("", 1, -2))
	t.assert_equals("い", util.char_sub("あいう", 2, 2))
end)

t.test("starts_with / ends_with", function()
	t.assert_true(util.starts_with("かな", "か"))
	t.assert_true(not util.starts_with("かな", "な"))
	t.assert_true(util.ends_with("かな", "な"))
	t.assert_true(util.ends_with("anything", ""))
end)

t.test("detect_encoding", function()
	t.assert_equals("utf-8", util.detect_encoding("こんにちは"))
	t.assert_equals("utf-8", util.detect_encoding("hello"))
	local euc = vim.iconv("こんにちは", "utf-8", "euc-jp")
	t.assert_equals("euc-jp", util.detect_encoding(euc))
	local sjis = vim.iconv("こんにちは", "utf-8", "cp932")
	t.assert_equals("cp932", util.detect_encoding(sjis))
end)

t.test("read_file_with_encoding", function()
	local tmp = t.tempname()
	local f = assert(io.open(tmp, "wb"))
	f:write(vim.iconv("てすと /テスト/\n", "utf-8", "euc-jp"))
	f:close()
	-- 明示指定
	t.assert_equals("てすと /テスト/\n", util.read_file_with_encoding(tmp, "euc-jp"))
	-- 自動判定
	t.assert_equals("てすと /テスト/\n", util.read_file_with_encoding(tmp, ""))
	os.remove(tmp)
end)

t.test("distinct", function()
	t.assert_equals({ 1, 2, 3 }, util.distinct({ 1, 2, 1, 3, 2 }))
	local a = { { "k", 1 }, { "k", 2 }, { "j", 3 } }
	local d = util.distinct(a, function(e)
		return e[1]
	end)
	t.assert_equals({ { "k", 1 }, { "j", 3 } }, d)
end)

t.test("okuri", function()
	local get_okuri_str = require("skkelua.okuri").get_okuri_str
	t.assert_equals("おくr", get_okuri_str("おく", "り"))
	t.assert_equals("うたがt", get_okuri_str("うたが", "っ"))
	t.assert_equals("うたがt", get_okuri_str("うたが", "って"))
	t.assert_equals("はしr", get_okuri_str("はし", "れば"))
end)

t.test("candidate modify", function()
	local modify = require("skkelua.candidate").modify_candidate
	t.assert_equals("注釈", modify("注釈;これは注釈です"))
	t.assert_equals("接頭", modify("接頭>", "prefix"))
	t.assert_equals("接尾", modify(">接尾", "suffix"))
	t.assert_equals(nil, modify(nil))
end)
