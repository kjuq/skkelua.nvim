-- pureSpace オプションのテスト
--
-- Note: tests/helper.lua の t.dispatch は " " を henkan_first に
--       ハードコードしているため、_handle_request の実経路
--       (keymap -> kanaInput -> kanatable) で検証する

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

--- キー列を handle_request 経由で流し、出力を連結して返す
---@param keys string[]
---@return string
local function feed(keys)
	local skkelua = require("skkelua")
	local out = {}
	for _, k in ipairs(keys) do
		local ret = skkelua._handle_request("handleKey", { key = { k } }, {
			mode = "",
			prevInput = require("skkelua.store").get_context():to_string(),
			completeInfo = {},
			completeType = "",
		})
		out[#out + 1] = ret.result
	end
	return table.concat(out)
end

t.test("pureSpace commits conversion input and inserts a space", function()
	local skkelua = require("skkelua")
	skkelua.config({ pureSpace = true })
	local ok, err = pcall(function()
		skkelua._handle_request("enable", {}, vim_status)

		-- ▽かんじ + Space: 変換を開始せず、ひらがなのまま確定 + 空白
		feed({ "K", "a", "n", "j", "i" })
		t.assert_equals("▽かんじ", skkelua.get_pre_edit())
		local out = feed({ "<space>" })
		t.assert_true(vim.endswith(out, "かんじ "), "output: " .. vim.inspect(out))
		t.assert_equals("", skkelua.get_pre_edit())
		t.assert_equals("input", skkelua.phase())
	end)
	skkelua.config({ pureSpace = false })
	if not ok then
		error(err, 0)
	end
end)

t.test("pureSpace commits the selected candidate in henkan", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "あ", "亜")
	skkelua.config({ pureSpace = true })
	local ok, err = pcall(function()
		skkelua._handle_request("enable", {}, vim_status)

		-- ▼亜 + Space: 候補送りではなく、選択中の候補で確定 + 空白
		feed({ "A" })
		skkelua._handle_request("handleKey", { ["function"] = "henkanFirst", key = { "" } }, {
			mode = "",
			prevInput = require("skkelua.store").get_context():to_string(),
			completeInfo = {},
			completeType = "",
		})
		t.assert_equals("henkan", skkelua.phase())
		local out = feed({ "<space>" })
		t.assert_true(vim.endswith(out, "亜 "), "output: " .. vim.inspect(out))
		t.assert_equals("input", skkelua.phase())
	end)
	skkelua.config({ pureSpace = false })
	if not ok then
		error(err, 0)
	end
end)

t.test("pureSpace keeps plain space and z-space intact", function()
	local skkelua = require("skkelua")
	skkelua.config({ pureSpace = true })
	local ok, err = pcall(function()
		skkelua._handle_request("enable", {}, vim_status)

		-- 直接入力の Space はただの空白
		t.assert_equals(" ", feed({ "<space>" }))
		-- z<Space> (feed 付きエントリ) は全角スペースのまま
		local out = feed({ "z", "<space>" })
		t.assert_true(vim.endswith(out, "　"), "output: " .. vim.inspect(out))
	end)
	skkelua.config({ pureSpace = false })
	if not ok then
		error(err, 0)
	end
end)

t.test("space reverts to henkanFirst when pureSpace is turned off", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "あ", "亜")

	-- true -> false と切り替えても従来動作 (Space で変換開始) に戻る
	skkelua.config({ pureSpace = true })
	skkelua.config({ pureSpace = false })
	skkelua._handle_request("enable", {}, vim_status)
	feed({ "A" })
	feed({ "<space>" })
	t.assert_equals("henkan", skkelua.phase())
end)
