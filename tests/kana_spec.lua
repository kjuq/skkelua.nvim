-- kana_test.ts の移植

local t = require("tests.helper")

local function find(entries, key)
	for _, e in ipairs(entries) do
		if e[1] == key then
			return e[2]
		end
	end
end

t.test("customize kanatable", function()
	t.clean_dictionary_config()
	local kana = require("skkelua.kana")
	kana.register_kana_table("rom", {
		["jj"] = "newline",
		["z,"] = { "―", "" },
		["z."] = { "―" },
		["!"] = { "!!" },
    ["z1"] = { "も*う", "" },
		["z2"] = { [[a\*b\\c]], "" },
	})
	-- can delete kana with falsy value
	kana.register_kana_table("rom", {
		["!"] = false,
	})
	local context = require("skkelua.context").new()
	t.dispatch(context, "jj")
	t.assert_equals("\r", context.preEdit:output(""))
	t.dispatch(context, "z,")
	t.assert_equals("―", context.preEdit:output(""))
	t.dispatch(context, "z.")
	t.assert_equals("―", context.preEdit:output(""))
	t.dispatch(context, "!")
	t.assert_equals("!", context.preEdit:output(""))
  -- "*" splits okuri but is not output; "\*" and "\\" are escapes
	t.dispatch(context, "z1")
	t.assert_equals("もう", context.preEdit:output(""))
	t.assert_equals({ "も", "う" }, find(kana.get_kana_table("rom"), "z1").okuriSplit)
	t.dispatch(context, "z2")
	t.assert_equals([[a*b\c]], context.preEdit:output(""))
end)

t.test("create kanatable", function()
	t.clean_dictionary_config()
	local kana = require("skkelua.kana")
	local config = require("skkelua.config").config
	kana.register_kana_table("test", {
		a = { "hoge", "" },
	}, true)
	config.kanaTable = "test"
	local skkelua = require("skkelua")
	skkelua._handle_request("enable", {}, {
		mode = "",
		prevInput = "",
		completeInfo = {},
		completeType = "",
	})
	local context = require("skkelua.store").get_context()
	t.dispatch(context, "a")
	t.assert_equals("hoge", context.preEdit:output(""))
	skkelua.disable_impl()
end)

t.test("kana table file", function()
	t.clean_dictionary_config()
	local kana = require("skkelua.kana")
	local tmp = t.tempname()
	local f = assert(io.open(tmp, "wb"))
	f:write("# comment\nka,か\nxx,っ\nmp,も*う\n\n")
	f:close()
	kana.load_kana_table_file("file_table", tmp, "utf-8", true)
	local table_ = kana.get_kana_table("file_table")
	t.assert_true(#table_ == 3)
	os.remove(tmp)
end)
