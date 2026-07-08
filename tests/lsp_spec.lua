-- LSP 補完ソースのテスト
--
-- Note: headless (-l) では pum 表示 (complete()) 自体は検証できないため、
--       completion list の組み立てと autotrigger からのリクエストフローを確認する

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

local function setup_library()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")
	lib:register_henkan_result("okurinasi", "かんじょう", "感情")
	lib:register_henkan_result("okurinasi", "かんが", "考;かんがえる")
end

--- ▽かんじ の変換入力状態を作り、バッファにも同じテキストを置く
local function setup_henkan_state()
	local skkelua = require("skkelua")
	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		skkelua._handle_request("handleKey", { key = { k } }, {
			mode = "",
			prevInput = require("skkelua.store").get_context():to_string(),
			completeInfo = {},
			completeType = "",
		})
	end
	local pre_edit = skkelua.get_pre_edit()
	t.assert_equals("▽かんじ", pre_edit)
	vim.cmd.enew({ bang = true })
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { pre_edit })
	vim.api.nvim_win_set_cursor(0, { 1, #pre_edit })
	return { position = { line = 0, character = #pre_edit } }
end

t.test("completion list for henkan input", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	local params = setup_henkan_state()

	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_equals(true, list.isIncomplete)
	t.assert_equals(3, #list.items)

	local by_label = {}
	for _, item in ipairs(list.items) do
		by_label[item.label] = item
	end
	-- 完全一致見出しの候補
	local kanji = by_label["漢字"]
	t.assert_true(kanji ~= nil)
	t.assert_equals("▽かんじ", kanji.filterText)
	t.assert_equals("漢字", kanji.textEdit.newText)
	-- 確定時に pre-edit を newText で置換させるため Snippet format を使う
	t.assert_equals(vim.lsp.protocol.InsertTextFormat.Snippet, kanji.insertTextFormat)
	-- ▽かんじ (12 bytes) 全体を置換する
	t.assert_equals({ line = 0, character = 0 }, kanji.textEdit.range.start)
	t.assert_equals({ line = 0, character = 12 }, kanji.textEdit.range["end"])
	t.assert_equals({ skkelua = true, midasi = "かんじ", word = "漢字" }, kanji.data)

	-- 前方一致見出し (かんじょう) の候補も出る
	local kanjou = by_label["感情"]
	t.assert_true(kanjou ~= nil)
	t.assert_equals("▽かんじょう", kanjou.filterText)

	-- 「かんが」は「かんじ」の前方一致ではないので出ない
	t.assert_equals(nil, by_label["考"])

	vim.cmd.bwipeout({ bang = true })
end)

t.test("annotation is stripped from insert text", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	-- ▽かんが を作る
	for _, k in ipairs({ "K", "a", "n", "g", "a" }) do
		skkelua._handle_request("handleKey", { key = { k } }, {
			mode = "",
			prevInput = require("skkelua.store").get_context():to_string(),
			completeInfo = {},
			completeType = "",
		})
	end
	local pre_edit = skkelua.get_pre_edit()
	vim.cmd.enew({ bang = true })
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { pre_edit })
	vim.api.nvim_win_set_cursor(0, { 1, #pre_edit })

	local list = require("skkelua.lsp")._make_completion_list({
		position = { line = 0, character = #pre_edit },
	})
	t.assert_equals(1, #list.items)
	local item = list.items[1]
	-- 挿入テキストは注釈なし、登録用 data には原文を保持
	t.assert_equals("考", item.label)
	t.assert_equals("考", item.textEdit.newText)
	t.assert_equals("かんがえる", item.labelDetails.description)
	t.assert_equals("考;かんがえる", item.data.word)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("no candidates outside henkan input", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	local lsp_mod = require("skkelua.lsp")

	-- 無効時
	t.assert_equals(0, #lsp_mod._make_completion_list({ position = { line = 0, character = 0 } }).items)

	-- 有効だが direct モード
	skkelua._handle_request("enable", {}, vim_status)
	t.assert_equals(0, #lsp_mod._make_completion_list({ position = { line = 0, character = 0 } }).items)

	-- バッファ内容が pre-edit と一致しない場合
	setup_henkan_state()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unrelated" })
	t.assert_equals(0, #lsp_mod._make_completion_list({ position = { line = 0, character = 9 } }).items)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("autotrigger sends completion request", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	local lsp_mod = require("skkelua.lsp")
	lsp_mod._requests = {}

	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	-- in-process サーバーの initialize と autotrigger の debounce を
	-- feed の中で消化するための待ちキー
	vim.keymap.set("i", "<F7>", function()
		vim.wait(500, function()
			return #lsp_mod._requests > 0
		end, 10)
	end, { buffer = true })

	local ok, err = pcall(function()
		vim.fn.feedkeys(vim.api.nvim_replace_termcodes("iJ<F7>Kanji<F7>", true, true, true), "tx")
		t.assert_true(#lsp_mod._requests >= 1, "completion request should be sent")
		local last = lsp_mod._requests[#lsp_mod._requests]
		t.assert_equals(3, last.items)
	end)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
end)

t.test("complete_callback registers the selected candidate", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	setup_henkan_state()

	-- CompleteDone 相当の処理 (data 付き候補の確定)
	skkelua.complete_callback("かんじ", "漢字")
	local lib = require("skkelua.store").get_library()
	local candidates = lib:get_henkan_result("okurinasi", "かんじ")
	t.assert_equals("漢字", candidates[1])
	vim.cmd.bwipeout({ bang = true })
end)
