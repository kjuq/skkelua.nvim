-- kana_test.ts の移植

local t = require("tests.helper")

t.test("customize kanatable", function()
	t.clean_dictionary_config()
	local kana = require("skkeleton.kana")
	kana.register_kana_table("rom", {
		["jj"] = "newline",
		["z,"] = { "―", "" },
		["z."] = { "―" },
		["!"] = { "!!" },
	})
	-- can delete kana with falsy value
	kana.register_kana_table("rom", {
		["!"] = false,
	})
	local context = require("skkeleton.context").new()
	t.dispatch(context, "jj")
	t.assert_equals("\n", context.preEdit:output(""))
	t.dispatch(context, "z,")
	t.assert_equals("―", context.preEdit:output(""))
	t.dispatch(context, "z.")
	t.assert_equals("―", context.preEdit:output(""))
	t.dispatch(context, "!")
	t.assert_equals("!", context.preEdit:output(""))
end)

t.test("create kanatable", function()
	t.clean_dictionary_config()
	local kana = require("skkeleton.kana")
	local config = require("skkeleton.config").config
	kana.register_kana_table("test", {
		a = { "hoge", "" },
	}, true)
	config.kanaTable = "test"
	local skkeleton = require("skkeleton")
	skkeleton._handle_request("enable", {}, {
		mode = "",
		prevInput = "",
		completeInfo = {},
		completeType = "",
	})
	local context = require("skkeleton.store").get_context()
	t.dispatch(context, "a")
	t.assert_equals("hoge", context.preEdit:output(""))
	skkeleton.disable_impl()
end)

t.test("kana table file", function()
	t.clean_dictionary_config()
	local kana = require("skkeleton.kana")
	local tmp = t.tempname()
	local f = assert(io.open(tmp, "wb"))
	f:write("# comment\nka,か\nxx,っ\n\n")
	f:close()
	kana.load_kana_table_file("file_table", tmp, "utf-8", true)
	local table_ = kana.get_kana_table("file_table")
	t.assert_true(#table_ == 2)
	os.remove(tmp)
end)
