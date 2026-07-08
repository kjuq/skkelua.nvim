-- function/henkan_test.ts の移植

local t = require("tests.helper")

local function setup_library()
	t.clean_dictionary_config()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "へんかん", "返還")
	lib:register_henkan_result("okurinasi", "へんかん", "変換")
	lib:register_henkan_result("okuriari", "おくr", "送")
	lib:register_henkan_result("okuriari", "えらn", "選")
	lib:register_henkan_result("okuriari", "うたがt", "疑")
	lib:register_henkan_result("okuriari", "うたがc", "疑")
	return lib
end

local function new_context()
	return require("skkelua.context").new()
end

t.test("okurinasi henkan", function()
	setup_library()
	local context = new_context()
	t.dispatch(context, ";henkan ")
	t.assert_equals("▼変換", context:to_string())
	t.dispatch(context, " ")
	t.assert_equals("▼返還", context:to_string())
	t.dispatch(context, "x")
	t.assert_equals("▼変換", context:to_string())
end)

t.test("okuriari henkan", function()
	setup_library()
	do
		local context = new_context()
		t.dispatch(context, ";oku;ri")
		t.assert_equals("▼送り", context:to_string())
	end
	do
		local context = new_context()
		t.dispatch(context, ";era;nde")
		t.assert_equals("▼選んで", context:to_string())
	end
	do
		local context = new_context()
		t.dispatch(context, ";utaga;tte")
		t.assert_equals("▼疑って", context:to_string())
	end
	do
		local context = new_context()
		t.dispatch(context, ";utaga;ccha")
		t.assert_equals("▼疑っちゃ", context:to_string())
	end
end)

t.test("henkan cancel", function()
	setup_library()
	local context = new_context()
	t.dispatch(context, ";henkan x")
	t.assert_equals("▽へんかん", context:to_string())
end)

t.test("fallback to kanaInput in henkanFirst", function()
	setup_library()
	local henkan_first = require("skkelua.function.henkan").henkan_first
	local context = new_context()
	context.state.table = { { " ", { "", "space" } } }
	t.dispatch(context, " ")
	t.assert_equals("space", context:to_string())
	-- avoid infinite recursion
	-- fallback to direct input
	context.state.table = { { " ", henkan_first } }
	t.dispatch(context, " ")
	t.assert_equals(" ", context.preEdit:output(""))
end)
