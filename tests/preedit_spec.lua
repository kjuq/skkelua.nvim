-- preedit_test.ts の移植

local t = require("tests.helper")
local PreEdit = require("skkelua.preedit").PreEdit

t.test("preedit test", function()
	local pre_edit = PreEdit.new()
	-- `PreEdit` remembers previous string length
	-- return value is remove current string and new string
	t.assert_equals("foo", pre_edit:output("foo"))
	t.assert_equals("\b\b\bhoge", pre_edit:output("hoge"))
	t.assert_equals("\b\b\b\bpiyo", pre_edit:output("piyo"))
	-- output kakutei before new string
	pre_edit:do_kakutei("bar")
	t.assert_equals("\b\b\b\bbarbaz", pre_edit:output("baz"))
end)

t.test("preedit with grapheme", function()
	local pre_edit = PreEdit.new()
	t.assert_equals("💩", pre_edit:output("💩"))
	t.assert_equals("\b🚽", pre_edit:output("🚽"))
	t.assert_equals("\b☀️", pre_edit:output("☀️")) -- U+2600 U+FE0F の合成文字
	t.assert_equals("\b🍦", pre_edit:output("🍦"))
end)

t.test("preedit with japanese", function()
	local pre_edit = PreEdit.new()
	t.assert_equals("▽か", pre_edit:output("▽か"))
	t.assert_equals("\b\bかき", pre_edit:output("かき"))
end)
