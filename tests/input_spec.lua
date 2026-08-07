-- function/input_test.ts の移植

local t = require("tests.helper")

local function new_context()
	return require("skkelua.context").new()
end

t.test("kana input", function()
	local context = new_context()
	t.dispatch(context, "nihongoutteiki")
	t.assert_equals("にほんごうっていき", context.preEdit:output(""))
end)

t.test("kana input with illegal key", function()
	do
		local context = new_context()
		t.dispatch(context, "n n n n ")
		t.assert_equals("ん ん ん ん ", context.preEdit:output(""))
	end
	do
		local context = new_context()
		t.dispatch(context, "@a")
		t.assert_equals("@あ", context.preEdit:output(""))
	end
	do
		local context = new_context()
		t.dispatch(context, " na")
		t.assert_equals(" な", context.preEdit:output(""))
	end
end)

t.test("kana input ignores control characters", function()
	local input = require("skkelua.function.input")
	local context = new_context()
	-- keymap 未割り当ての特殊キー (<C-n> = \14 など) が流れてきても
	-- pre-edit に混入しない
	t.dispatch(context, "Muko")
	input.kana_input(context, "\14")
	input.kana_input(context, "\16")
	t.assert_equals("▽むこ", context:to_string())
	-- 確定文字列にも混ざらない
	input.kana_input(context, "u")
	t.assert_equals("▽むこう", context:to_string())
end)

t.test("henkan point", function()
	local context = new_context()
	local tests = {
		{ ";", "▽" },
		{ ";", "▽" },
		{ "y", "▽y" },
		{ "a", "▽や" },
		{ ";", "▽や*" },
		{ ";", "▽や*" },
		{ "t", "▽や*t" },
		{ "t", "▽や*っt" },
		{ ";", "▽や*っt" },
	}
	for _, tc in ipairs(tests) do
		t.dispatch(context, tc[1])
		t.assert_equals(tc[2], context:to_string())
	end
end)

t.test("upper case input", function()
	do
		local context = new_context()
		t.dispatch(context, "HogeP")
		t.assert_equals("▽ほげ*p", context:to_string())
	end
	do
		local context = new_context()
		t.dispatch(context, "sAsS")
		t.assert_equals("▽さっ*s", context:to_string())
	end
end)

t.test("upper case input with lowercaseMap", function()
	local config = require("skkelua.config").config
	config.lowercaseMap = { ["+"] = "a" }
	local context = new_context()
	t.dispatch(context, "+")
	t.assert_equals("▽あ", context:to_string())
end)

t.test("delete char", function()
	local util = require("skkelua.util")
	local delete_char = require("skkelua.function.input").delete_char
	local context = new_context()
	t.dispatch(context, ";ya;tt")
	local result = context:to_string()
	repeat
		delete_char(context)
		result = util.char_sub(result, 1, -2)
		-- 最後の 1 文字を消したら ▽ は単独で残らず、変換モードごと抜ける
		if result == "▽" then
			result = ""
		end
		t.assert_equals(result, context:to_string())
	until result == ""
end)

t.test("undo point", function()
	do
		local context = new_context()
		context.vimMode = "i"
		t.dispatch(context, "a")
		require("skkelua.function.input").henkan_point(context)
		t.assert_equals("あ\7u▽", context.preEdit:output(context:to_string()))
	end
	-- not emit at cmdline
	do
		local context = new_context()
		context.vimMode = "c"
		t.dispatch(context, "a")
		require("skkelua.function.input").henkan_point(context)
		t.assert_equals("あ▽", context.preEdit:output(context:to_string()))
	end
end)

t.test("katakana input", function()
	t.clean_dictionary_config()
	local katakana = require("skkelua.function.mode").katakana
	local hankatakana = require("skkelua.function.mode").hankatakana
	local kakutei = require("skkelua.function.common").kakutei
	local context = new_context()

	-- change to katakana mode
	katakana(context)
	t.dispatch(context, "a")
	t.assert_equals("ア", context.preEdit:output(""))
	katakana(context)
	t.dispatch(context, "a")
	t.assert_equals("あ", context.preEdit:output(""))

	-- henkan pre
	katakana(context)
	t.dispatch(context, "N")
	t.assert_equals("▽n", context:to_string())
	-- and kakutei
	kakutei(context)
	t.assert_equals("ン", context.preEdit:output(""))

	katakana(context)
	-- convert henkan pre
	t.dispatch(context, "Hoge")
	katakana(context)
	t.assert_equals("ホゲ", context.preEdit:output(""))
	-- from hankatakana mode
	hankatakana(context)
	t.dispatch(context, "Hoge")
	katakana(context)
	t.assert_equals("ほげ", context.preEdit:output(""))
	hankatakana(context)
	-- don't convert when converter enabled
	katakana(context)
	t.dispatch(context, "Hoge")
	katakana(context)
	t.assert_equals("ほげ", context.preEdit:output(""))
end)

t.test("hankatakana input", function()
	t.clean_dictionary_config()
	local katakana = require("skkelua.function.mode").katakana
	local hankatakana = require("skkelua.function.mode").hankatakana
	local kakutei = require("skkelua.function.common").kakutei
	local context = new_context()

	-- change to hankatakana mode
	hankatakana(context)
	t.dispatch(context, "a")
	t.assert_equals("ｱ", context.preEdit:output(""))
	hankatakana(context)
	t.dispatch(context, "a")
	t.assert_equals("あ", context.preEdit:output(""))
	-- from katakana mode
	katakana(context)
	hankatakana(context)
	t.dispatch(context, "a")
	t.assert_equals("ｱ", context.preEdit:output(""))
	-- katakana() in hankana mode to move to hiragana mode
	katakana(context)
	t.dispatch(context, "a")
	t.assert_equals("あ", context.preEdit:output(""))

	-- henkan pre
	hankatakana(context)
	t.dispatch(context, "N")
	t.assert_equals("▽n", context:to_string())
	-- and kakutei
	kakutei(context)
	t.assert_equals("ﾝ", context.preEdit:output(""))

	hankatakana(context)
	-- convert henkan pre
	t.dispatch(context, "Hoge")
	hankatakana(context)
	t.assert_equals("ﾎｹﾞ", context.preEdit:output(""))
	-- from katakana mode
	katakana(context)
	t.dispatch(context, "Hoge")
	hankatakana(context)
	t.assert_equals("ﾎｹﾞ", context.preEdit:output(""))
	katakana(context)
	-- don't convert when converter enabled
	hankatakana(context)
	t.dispatch(context, "Hoge")
	hankatakana(context)
	t.assert_equals("ほげ", context.preEdit:output(""))
end)

-- test({mode: "nvim", name: "new line"}) の移植
-- 実バッファへの feedkeys 統合テスト
t.test("new line (integration)", function()
	t.clean_dictionary_config()
	vim.cmd.enew({ bang = true })
	vim.bo.autoindent = true
	vim.cmd("inoremap J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	vim.fn.feedkeys("iJ\thoge\13hoge;hoge\13", "tx")
	t.assert_equals({ "\tほげ", "\tほげほげ", "" }, vim.fn.getline(1, "$"))
	vim.cmd("iunmap J")
	vim.cmd.bwipeout({ bang = true })
end)
