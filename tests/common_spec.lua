-- function/common_test.ts の移植

local t = require("tests.helper")

local function setup_library()
	t.clean_dictionary_config()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "あ", "い")
	lib:register_henkan_result("okurinasi", "ちゅうしゃく", "注釈;これは注釈です")
	return lib
end

t.test("input cancel", function()
	setup_library()
	local config = require("skkelua.config").config
	local cancel = require("skkelua.function.common").cancel
	local context = require("skkelua.context").new()
	t.dispatch(context, "A")
	cancel(context)
	t.assert_equals("", context:to_string())
	t.dispatch(context, "A ")
	cancel(context)
	t.assert_equals("", context:to_string())

	config.immediatelyCancel = false
	t.dispatch(context, "A ")
	cancel(context)
	t.assert_equals("▽あ", context:to_string())
	cancel(context)
	t.assert_equals("", context:to_string())
end)

t.test("annotation", function()
	local lib = setup_library()
	local kakutei = require("skkelua.function.common").kakutei
	local context = require("skkelua.context").new()
	t.dispatch(context, ";tyuusyaku ")
	kakutei(context)
	t.assert_equals("注釈", context.preEdit:output(""))
	t.assert_equals(
		{ "注釈;これは注釈です" },
		lib:get_henkan_result("okurinasi", "ちゅうしゃく")
	)
end)

t.test("turn off mode when kakutei with empty input", function()
	setup_library()
	local katakana = require("skkelua.function.mode").katakana
	local kakutei_key = require("skkelua.function.common").kakutei_key
	local context = require("skkelua.context").new()
	katakana(context)
	t.dispatch(context, "k")
	kakutei_key(context)
	t.assert_equals("kata", context.mode)
	kakutei_key(context)
	t.assert_equals("hira", context.mode)
end)
