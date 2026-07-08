-- function/disable_test.ts の移植

local t = require("tests.helper")

t.test("kakutei at disable", function()
	t.clean_dictionary_config()
	local skkeleton = require("skkeleton")
	local store = require("skkeleton.store")
	local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }
	skkeleton._handle_request("enable", {}, vim_status)
	t.dispatch(store.get_context(), " ")
	local ret = skkeleton._handle_request("disable", {}, vim_status)
	t.assert_equals(" ", ret.result)

	skkeleton._handle_request("enable", {}, vim_status)
	t.dispatch(store.get_context(), "n")
	local vim_status2 = { mode = "", prevInput = "n", completeInfo = {}, completeType = "" }
	local ret2 = skkeleton._handle_request("disable", {}, vim_status2)
	t.assert_equals("ん", ret2.result)
end)

t.test("disable just after completion", function()
	t.clean_dictionary_config()
	local skkeleton = require("skkeleton")
	local store = require("skkeleton.store")
	local vim_status = { mode = "", prevInput = "変換結果", completeInfo = {}, completeType = "" }
	skkeleton._handle_request("enable", {}, vim_status)
	local context = store.get_context()
	t.dispatch(context, ";hoge")
	skkeleton._handle_request("disable", { key = {} }, vim_status)
	t.assert_equals(false, vim.g["skkeleton#enabled"])
end)

t.test("escape state", function()
	t.clean_dictionary_config()
	local store = require("skkeleton.store")
	local context = store.get_context()
	require("skkeleton.function.disable").escape(context)
	t.assert_equals("escape", context.state.type)
	t.assert_equals("\27", context:to_string())
end)
