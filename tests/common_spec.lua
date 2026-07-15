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

t.test("deletePreEdit clears the whole pre-edit", function()
	setup_library()
	local delete_pre_edit = require("skkelua.function.common").delete_pre_edit
	local context = require("skkelua.context").new()

	-- ▽ 変換入力中: マーカーごと全て消える
	t.dispatch(context, "Kanji")
	t.assert_equals("▽かんじ", context:to_string())
	delete_pre_edit(context, "\23")
	t.assert_equals("", context:to_string())
	t.assert_equals("input", context.state.type)

	-- ▼ 候補選択中: 同じく全て消える
	t.dispatch(context, "A ")
	t.assert_equals("▼い", context:to_string())
	delete_pre_edit(context, "\23")
	t.assert_equals("", context:to_string())

	-- abbrev 入力中: 消えてかなモードへ戻る
	t.dispatch(context, "/abc")
	t.assert_equals("▽abc", context:to_string())
	delete_pre_edit(context, "\23")
	t.assert_equals("", context:to_string())
	t.assert_equals("hira", context.mode)

	-- 直接入力: キー本来の動作 (単語削除) に任せるためそのまま通す
	delete_pre_edit(context, "\23")
	t.assert_equals("\23", context.preEdit:output(""))
end)

t.test("C-w is mapped to deletePreEdit by default", function()
	local keymap = require("skkelua.keymap")
	t.assert_equals("deletePreEdit", keymap._get("input", "<c-w>"))
	t.assert_equals("deletePreEdit", keymap._get("henkan", "<c-w>"))
	t.assert_true(vim.tbl_contains(require("skkelua").get_default_mapped_keys(), "<C-w>"))
end)

t.test("passThrough keeps conversion state on Tab", function()
	setup_library()
	local pass_through = require("skkelua.function.common").pass_through
	local context = require("skkelua.context").new()

	-- ▽ 変換入力中: 何も起きず状態も表示も変わらない
	t.dispatch(context, "A")
	t.assert_equals("▽あ", context:to_string())
	pass_through(context, "\t")
	t.assert_equals("▽あ", context:to_string())
	t.assert_equals("input", context.state.type)
	t.assert_equals("okurinasi", context.state.mode)

	-- ▼ 候補選択中: 同じく無視
	t.dispatch(context, " ")
	t.assert_equals("▼い", context:to_string())
	pass_through(context, "\t")
	t.assert_equals("▼い", context:to_string())

	-- 直接入力: キー本来の動作 (Tab 挿入) に任せるためそのまま通す
	require("skkelua.function.common").kakutei(context)
	context.preEdit:output(context:to_string())
	pass_through(context, "\t")
	t.assert_equals("\t", context.preEdit:output(""))
end)

t.test("Tab is mapped to passThrough by default", function()
	local keymap = require("skkelua.keymap")
	t.assert_equals("passThrough", keymap._get("input", "<tab>"))
	t.assert_equals("passThrough", keymap._get("henkan", "<tab>"))
	t.assert_equals("passThrough", keymap._get("input", "<s-tab>"))
	t.assert_equals("passThrough", keymap._get("henkan", "<s-tab>"))
	local keys = require("skkelua").get_default_mapped_keys()
	t.assert_true(vim.tbl_contains(keys, "<Tab>"))
	t.assert_true(vim.tbl_contains(keys, "<S-Tab>"))
end)

t.test("kana commit drops the affix marker", function()
	setup_library()
	local kakutei = require("skkelua.function.common").kakutei

	-- 接尾辞入力 (▽>けい) のかな確定は「けい」だけになる
	local context = require("skkelua.context").new()
	context.state.mode = "okurinasi"
	context.state.henkanFeed = ">けい"
	context.state.affix = "suffix"
	kakutei(context)
	t.assert_equals("けい", context.preEdit:output(""))

	-- ▽> 単独の確定では何も残らない
	context = require("skkelua.context").new()
	context.state.mode = "okurinasi"
	context.state.henkanFeed = ">"
	context.state.affix = "suffix"
	kakutei(context)
	t.assert_equals("", context.preEdit:output(""))

	-- 接頭辞入力 (▽こう>) は末尾の > が落ちる
	context = require("skkelua.context").new()
	context.state.mode = "okurinasi"
	context.state.henkanFeed = "こう>"
	context.state.affix = "prefix"
	kakutei(context)
	t.assert_equals("こう", context.preEdit:output(""))

	-- 接辞でない通常のかな確定は変わらない
	context = require("skkelua.context").new()
	t.dispatch(context, "A")
	kakutei(context)
	t.assert_equals("あ", context.preEdit:output(""))
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
