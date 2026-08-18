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

--- vim.fn.confirm を差し替えて実行し、必ず元に戻す
---@param answer integer
---@param fn fun(): (string?) メッセージを捕捉する必要が無ければ何も返さなくて良い
---@return string? captured_msg
local function with_confirm_stub(answer, fn)
	local orig_confirm = vim.fn.confirm
	local msg
	vim.fn.confirm = function(m)
		msg = m
		return answer
	end
	local ok, err = pcall(fn)
	vim.fn.confirm = orig_confirm
	if not ok then
		error(err, 0)
	end
	return msg
end

t.test("purgeCandidate removes the henkan candidate", function()
	local lib = setup_library()
	local purge_candidate = require("skkelua.function.common").purge_candidate
	local context = require("skkelua.context").new()

	t.dispatch(context, "A ")
	t.assert_equals("▼い", context:to_string())

	local msg = with_confirm_stub(1, function()
		purge_candidate(context, "X")
	end)
	t.assert_equals("Really purge? あ /い/", msg)
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "あ"))
end)

t.test("purgeCandidate uses lastCandidate right after committing in direct mode", function()
	local lib = setup_library()
	local common = require("skkelua.function.common")
	local context = require("skkelua.context").new()

	-- 確定直後は lastCandidate に直前の候補が残り、direct モードのままでも消せる
	t.dispatch(context, "A ")
	common.kakutei(context)
	t.assert_equals("い", context.lastCandidate.candidate)
	t.assert_equals("input", context.state.type)
	t.assert_equals("direct", context.state.mode)

	local msg = with_confirm_stub(1, function()
		common.purge_candidate(context, "X")
	end)
	t.assert_equals("Really purge? あ /い/", msg)
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "あ"))
end)

t.test("purgeCandidate falls back to kana input without any candidate to purge", function()
	setup_library()
	local purge_candidate = require("skkelua.function.common").purge_candidate
	local context = require("skkelua.context").new()

	-- direct モードで pum フォーカスも lastCandidate も無ければ、
	-- 通常のかな入力 (大文字 X = 変換入力の開始) に委譲する
	purge_candidate(context, "X")
	t.assert_equals("▽x", context:to_string())
end)

t.test("purgeCandidate falls back to kana input while henkan input is in progress", function()
	setup_library()
	local purge_candidate = require("skkelua.function.common").purge_candidate
	local context = require("skkelua.context").new()

	-- 変換入力中 (okurinasi) の X は lastCandidate があっても変換入力を優先する
	context.lastCandidate = { type = "okurinasi", word = "あ", candidate = "い" }
	t.dispatch(context, "Kanji")
	t.assert_equals("▽かんじ", context:to_string())
	purge_candidate(context, "X")
	t.assert_equals("▽かんじ*x", context:to_string())
end)
