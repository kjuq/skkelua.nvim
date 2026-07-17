-- <C-y> (kakuteiPassThrough) と補完メニューの連携のテスト

local t = require("tests.helper")

local CTRL_Y = "\25"

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

--- prevInput を現在の pre-edit に合わせて handleKey を呼ぶ
---@param key string
---@param complete_info? table
---@param complete_type? string
local function handle_key(key, complete_info, complete_type)
	local skkelua = require("skkelua")
	return skkelua._handle_request("handleKey", { key = { key } }, {
		mode = "",
		prevInput = require("skkelua.store").get_context():to_string(),
		completeInfo = complete_info or {},
		completeType = complete_type or "",
	})
end

--- ▽かんじ の変換入力状態を作る
local function setup_henkan_input()
	local skkelua = require("skkelua")
	skkelua._handle_request("enable", {}, vim_status)
	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		handle_key(k)
	end
	t.assert_equals("▽かんじ", skkelua.get_pre_edit())
end

t.test("<C-y> with pum unselected commits kana as-is", function()
	local skkelua = require("skkelua")
	setup_henkan_input()

	local ret = handle_key("<c-y>", { pum_visible = 1, selected = -1 }, "native")
	-- ▽かんじ (4 文字) を消して、変換せずかなを確定する
	t.assert_equals("\b\b\b\bかんじ", ret.result)
	t.assert_equals("input", ret.state.phase)
	t.assert_equals("", skkelua.get_pre_edit())
end)

t.test("<C-y> with pum selected passes through to native confirm", function()
	local skkelua = require("skkelua")
	setup_henkan_input()

	local ret = handle_key("<c-y>", { pum_visible = 1, selected = 0 }, "native")
	-- 選択済み候補の確定は native の <C-y> に任せる (バッファは textEdit が置換する)
	t.assert_equals(CTRL_Y, ret.result)
	t.assert_equals("input", ret.state.phase)
	t.assert_equals("", skkelua.get_pre_edit())
end)

t.test("<C-y> with cmp selection returns cmp confirm command", function()
	setup_henkan_input()

	local ret = handle_key("<c-y>", { pum_visible = 1, selected = 1 }, "cmp")
	t.assert_equals("<Cmd>lua require('cmp').confirm({select = true})", ret.result)
end)

t.test("<C-y> on the selected [辞書登録] item keeps the henkan input state", function()
	local skkelua = require("skkelua")
	setup_henkan_input()

	-- [辞書登録] の挿入テキストは pre-edit そのものでバッファは変わらず、
	-- CompleteDone からの registerWord が変換入力の続きとして実行される。
	-- 確定キーへのパススルー時に状態をリセットしてはいけない
	local items = {
		{
			word = "▽かんじ",
			user_data = {
				nvim = {
					lsp = {
						completion_item = { data = { skkelua = true, register = true } },
					},
				},
			},
		},
	}
	local ret = handle_key("<c-y>", { pum_visible = 1, selected = 0, items = items }, "native")
	t.assert_equals(CTRL_Y, ret.result)
	t.assert_equals("input:okurinasi", ret.state.phase)
	t.assert_equals("▽かんじ", skkelua.get_pre_edit())
end)

t.test("<C-y> in direct input passes the key through", function()
	local skkelua = require("skkelua")
	skkelua._handle_request("enable", {}, vim_status)

	local ret = handle_key("<c-y>")
	t.assert_equals(CTRL_Y, ret.result)
	t.assert_equals("input", ret.state.phase)
end)

t.test("<C-y> in henkan state commits the current candidate", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	setup_henkan_input()

	handle_key("<space>")
	t.assert_equals("▼漢字", skkelua.get_pre_edit())

	local ret = handle_key("<c-y>", { pum_visible = 1, selected = -1 }, "native")
	t.assert_equals("\b\b\b漢字", ret.result)
	t.assert_equals("input", ret.state.phase)
	local context = require("skkelua.store").get_context()
	t.assert_equals("漢字", context.lastCandidate.candidate)
end)
