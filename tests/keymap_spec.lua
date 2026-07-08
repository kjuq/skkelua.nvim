-- keymap_test.ts の移植

local t = require("tests.helper")

-- Note: skkeleton#handle はバッファと preEdit の一貫性を要求する
-- (不一致だと状態がリセットされる) ため、prevInput を preEdit に追随させる
local function handle_key(key)
	local skkeleton = require("skkeleton")
	local store = require("skkeleton.store")
	local vim_status = {
		mode = "",
		prevInput = store.get_context():to_string(),
		completeInfo = {},
		completeType = "",
	}
	skkeleton._handle_request("handleKey", { key = { key } }, vim_status)
end

t.test("registerKeyMap", function()
	t.clean_dictionary_config()
	local skkeleton = require("skkeleton")
	local store = require("skkeleton.store")
	local lib = store.get_library()
	lib:register_henkan_result("okurinasi", "あ", "亜")
	skkeleton.register_keymap("henkan", "x", "")
	skkeleton.register_keymap("henkan", "<BS>", "henkanBackward")

	-- fallback to default mapping because "x" was unmapped
	handle_key("A")
	handle_key(" ")
	handle_key("x")
	t.assert_equals("x", store.get_context():to_string())

	store.init_context()

	-- backward state with <BS>
	handle_key("A")
	handle_key(" ")
	handle_key("<bs>")
	t.assert_equals("▽あ", store.get_context():to_string())

	store.init_context()

	-- register a keymap that consists of a single capital letter
	skkeleton.register_keymap("henkan", "B", "henkanBackward")
	handle_key("A")
	handle_key(" ")
	handle_key("B")
	t.assert_equals("▽あ", store.get_context():to_string())

	store.init_context()

	-- remove a keymap registered above
	skkeleton.register_keymap("henkan", "B", "")
	handle_key("A")
	handle_key(" ")
	handle_key("B")
	t.assert_equals("▽b", store.get_context():to_string())
end)

t.test("send multiple keys into handleKey", function()
	t.clean_dictionary_config()
	local skkeleton = require("skkeleton")
	local store = require("skkeleton.store")
	local lib = store.get_library()
	lib:register_henkan_result("okurinasi", "われ", "我")
	lib:register_henkan_result("okuriari", "おもu", "思")

	local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }
	skkeleton._handle_request("handleKey", { key = { "W", "a", "r", "e" } }, vim_status)
	t.assert_equals("▽われ", store.get_context():to_string())

	store.init_context()

	skkeleton._handle_request("handleKey", { key = { "O", "m", "o", "U" } }, vim_status)
	t.assert_equals("▼思う", store.get_context():to_string())
end)
