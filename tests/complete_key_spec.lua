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

t.test("<C-y> with a non-skkelua pum item selected passes through to native confirm", function()
	local skkelua = require("skkelua")
	setup_henkan_input()

	-- 他の補完ソースの候補 (skkelua の data を持たない) は native の <C-y> に任せる
	local ret = handle_key("<c-y>", { pum_visible = 1, selected = 0, items = { { word = "other" } } }, "native")
	t.assert_equals(CTRL_Y, ret.result)
	t.assert_equals("input", ret.state.phase)
	t.assert_equals("", skkelua.get_pre_edit())
end)

local function tc(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- finalize_completion が出力の先頭に付ける、pum を閉じる <Cmd>
local REVERT_CMD = tc("<Cmd>")
	.. "lua local ok, m = pcall(require, 'skkelua') if ok then m._revert_completion() end"
	.. tc("<CR>")

--- skkelua の候補 (lsp.lua の item と同じ形) を選択中の complete_info
---@param word string
---@param extra? table data に足すフィールド
local function selected_info(word, extra)
	local data = { skkelua = true, midasi = "かんじ", word = word, type = "okurinasi", okuri = "", text = word }
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	return {
		pum_visible = 1,
		selected = 0,
		items = { { word = word, user_data = { nvim = { lsp = { completion_item = { data = data } } } } } },
	}
end

t.test("<C-y> with a skkelua item selected commits it with skkelua's own output", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")
	setup_henkan_input()

	local ret = handle_key("<c-y>", selected_info("漢字"), "native")
	-- pum を閉じて ▽かんじ (4 文字) を消し、候補を入れる。native の <C-y> は送らない
	t.assert_equals(REVERT_CMD .. "\b\b\b\b漢字", ret.result)
	t.assert_equals("input", ret.state.phase)
	t.assert_equals("", skkelua.get_pre_edit())
	-- 確定した候補はユーザー辞書へ登録される (native の確定を通らないため自前で行う)
	t.assert_equals("漢字", lib:get_henkan_result("okurinasi", "かんじ")[1])
	t.assert_equals("漢字", require("skkelua.store").get_context().lastCandidate.candidate)
end)

t.test("<CR> with a skkelua item selected commits it and inserts a newline", function()
	setup_henkan_input()
	local ret = handle_key("<cr>", selected_info("漢字"), "native")
	t.assert_equals(REVERT_CMD .. "\b\b\b\b漢字\r", ret.result)
end)

t.test("<CR> with eggLikeNewline commits the selected skkelua item only", function()
	require("skkelua.config").config.eggLikeNewline = true
	setup_henkan_input()
	local ret = handle_key("<cr>", selected_info("漢字"), "native")
	t.assert_equals(REVERT_CMD .. "\b\b\b\b漢字", ret.result)
end)

t.test("typing after an insertOnSelect selection commits the selected item first", function()
	local config = require("skkelua.config").config
	config.completion.insertOnSelect = true
	config.pureSpace = true
	setup_henkan_input()
	-- 選択挿入中はバッファが候補 word に置き換わっている (prevInput 不一致で
	-- direct へリセットされる) 状態で Space を打つ
	local ret = require("skkelua")._handle_request("handleKey", { key = { "<space>" } }, {
		mode = "",
		prevInput = "漢字",
		completeInfo = selected_info("漢字"),
		completeType = "native",
	})
	t.assert_equals(REVERT_CMD .. "\b\b\b\b漢字 ", ret.result)
end)

t.test("selection-aware keys do not commit the insertOnSelect selection", function()
	local config = require("skkelua.config").config
	config.completion.insertOnSelect = true
	setup_henkan_input()
	-- <C-w> (deletePreEdit) は選択挿入中の word をまとめて消す独自処理を持つので、
	-- 確定のキー列は付けない
	local ret = require("skkelua")._handle_request("handleKey", { key = { "<c-w>" } }, {
		mode = "",
		prevInput = "漢字",
		completeInfo = selected_info("漢字"),
		completeType = "native",
	})
	t.assert_true(not vim.startswith(ret.result, REVERT_CMD), ret.result)
end)

t.test("keys other than confirm keys do not commit without insertOnSelect", function()
	require("skkelua.config").config.completion.insertOnSelect = false
	setup_henkan_input()
	-- フォーカスだけの選択なので Space は skkelua 自身の変換 (候補送り) になる
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")
	local ret = handle_key("<space>", selected_info("漢字"), "native")
	t.assert_true(not vim.startswith(ret.result, REVERT_CMD), ret.result)
	t.assert_equals("henkan", ret.state.phase)
end)

t.test("raw abbrev candidate is committed without dictionary registration", function()
	local lib = require("skkelua.store").get_library()
	setup_henkan_input()
	local ret = handle_key("<c-y>", selected_info(" kanji", { raw = true, midasi = "kanji" }), "native")
	t.assert_equals(REVERT_CMD .. "\b\b\b\b kanji", ret.result)
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "kanji"))
end)

t.test("<C-y> with cmp selection returns cmp confirm command", function()
	setup_henkan_input()

	local saved = package.loaded["cmp"]
	package.loaded["cmp"] = {
		visible = function()
			return true
		end,
		get_active_entry = function()
			return {
				get_completion_item = function()
					return { data = { skkelua = true } }
				end,
			}
		end,
	}
	local status = require("skkelua").vim_status()
	local ok, ret = pcall(handle_key, "<c-y>", status.completeInfo, status.completeType)
	package.loaded["cmp"] = saved
	assert(ok, ret)
	t.assert_equals("<Cmd>lua require('cmp').confirm({select = true})", ret.result)
end)

t.test("<C-y> on the selected [辞書登録] item keeps the henkan input state", function()
	local skkelua = require("skkelua")
	setup_henkan_input()

	-- [辞書登録] の挿入テキストは pre-edit そのものでバッファは変わらず、
	-- 候補の command (skkelua.accept) からの registerWord が
	-- 変換入力の続きとして実行される。
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
