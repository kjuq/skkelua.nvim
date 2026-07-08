-- config_test.ts の移植

local t = require("tests.helper")

local function setup_library()
	t.clean_dictionary_config()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "あ", "あ")
	lib:register_henkan_result("okuriari", "あt", "会")
	lib:register_henkan_result("okuriari", "すp", "酸")
	return lib
end

t.test("egg like newline", function()
	setup_library()
	local config = require("skkelua.config").config
	local context = require("skkelua.context").new()
	-- normal
	t.dispatch(context, "A \nA\n")
	t.assert_equals("あ\nあ\n", context.preEdit:output(""))
	-- egg like
	config.eggLikeNewline = true
	t.dispatch(context, "A \nA\n")
	t.assert_equals("ああ", context.preEdit:output(""))
end)

t.test("acceptIllegalResult", function()
	setup_library()
	local config = require("skkelua.config").config
	do
		config.acceptIllegalResult = false
		local context = require("skkelua.context").new()
		t.dispatch(context, "ksa")
		t.assert_equals("さ", context.preEdit:output(""))
	end
	do
		config.acceptIllegalResult = true
		local context = require("skkelua.context").new()
		t.dispatch(context, "ksa")
		t.assert_equals("kさ", context.preEdit:output(""))
	end
end)

t.test("immediatelyOkuriConvert", function()
	setup_library()
	local config = require("skkelua.config").config
	-- true
	do
		local context = require("skkelua.context").new()
		t.dispatch(context, ";a;xtu")
		t.assert_equals("▼会っ", context:to_string())
	end
	-- false
	do
		config.immediatelyOkuriConvert = false
		local context = require("skkelua.context").new()
		t.dispatch(context, ";su;xtupa")
		t.assert_equals("▼酸っぱ", context:to_string())
	end
end)

t.test("keepMode", function()
	setup_library()
	local config = require("skkelua.config").config
	local store = require("skkelua.store")
	config.keepMode = true
	store.variables.lastMode = "hira"
	local skkelua = require("skkelua")
	local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }
	skkelua._handle_request("enable", {}, vim_status)
	require("skkelua.function.mode").katakana(store.get_context())
	require("skkelua.function.disable").disable(store.get_context())
	skkelua._handle_request("enable", {}, vim_status)
	t.assert_equals("kata", store.get_context().mode)
end)

t.test("set_config validation", function()
	local skkelua = require("skkelua")
	skkelua.config({
		eggLikeNewline = true,
		markerHenkan = ">>",
		showCandidatesCount = 5,
	})
	local config = require("skkelua.config").config
	t.assert_equals(true, config.eggLikeNewline)
	t.assert_equals(">>", config.markerHenkan)
	t.assert_equals(5, config.showCandidatesCount)

	-- 不正な値はエラー
	t.assert_error(function()
		skkelua.config({ eggLikeNewline = "yes" })
	end)
	t.assert_error(function()
		skkelua.config({ unknownOption = 1 })
	end)
	t.assert_error(function()
		skkelua.config({ selectCandidateKeys = "abc" })
	end)
	t.assert_error(function()
		skkelua.config({ useGoogleJapaneseInput = true })
	end)

	-- userDictionary の ~ 展開
	skkelua.config({ userDictionary = "~/.test-skkeleton" })
	t.assert_true(not vim.startswith(config.userDictionary, "~"))
end)
