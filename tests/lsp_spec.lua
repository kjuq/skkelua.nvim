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
	t.assert_equals(
		{ skkelua = true, midasi = "かんじ", word = "漢字", type = "okurinasi" },
		kanji.data
	)

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

--- 任意のキー列で変換入力状態を作り、バッファへ pre-edit を置く
local function setup_state(keys)
	local skkelua = require("skkelua")
	for _, k in ipairs(keys) do
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
	return pre_edit, { position = { line = 0, character = #pre_edit } }
end

t.test("completion during okuriari input", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "おくr", "送")
	lib:register_henkan_result("okuriari", "おくr", "遅")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)

	-- ▽おく*r (送りのローマ字だけがある状態)
	local pre_edit, params = setup_state({ "O", "k", "u", "R" })
	t.assert_equals("▽おく*r", pre_edit)
	t.assert_equals("input:okuriari", skkelua.phase())

	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_true(#list.items > 0, "okuriari candidates should be present")

	local by_label = {}
	for _, item in ipairs(list.items) do
		by_label[item.label] = item
	end
	-- 語幹 + ありうる送り仮名の完成形が並ぶ
	t.assert_true(by_label["送り"] ~= nil)
	t.assert_true(by_label["送る"] ~= nil)
	t.assert_true(by_label["遅れ"] ~= nil)
	-- 完成しない送り (っ を作る rr など) は含まれない
	t.assert_equals(nil, by_label["送っ"])

	local okuri = by_label["送り"]
	t.assert_equals("▽おく*r", okuri.filterText)
	t.assert_equals("送り", okuri.textEdit.newText)
	t.assert_equals("おくr", okuri.detail)
	t.assert_equals(
		{ skkelua = true, midasi = "おくr", word = "送", type = "okuriari" },
		okuri.data
	)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("okuriari completion with confirmed sokuon", function()
	local skkelua = require("skkelua")
	local config = require("skkelua.config").config
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "うたがt", "疑")
	config.immediatelyOkuriConvert = false
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)

	-- ▽うたが*っt (okuriFeed=っ が確定済みで feed=t が残る状態)
	local pre_edit, params = setup_state({ "U", "t", "a", "g", "a", "T", "t" })
	t.assert_equals("▽うたが*っt", pre_edit)

	local list = require("skkelua.lsp")._make_completion_list(params)
	local by_label = {}
	for _, item in ipairs(list.items) do
		by_label[item.label] = item
	end
	t.assert_true(by_label["疑った"] ~= nil)
	t.assert_true(by_label["疑って"] ~= nil)
	t.assert_equals("うたがt", by_label["疑った"].data.midasi)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("completion during henkan phase (candidate selection)", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "おくr", "送")
	lib:register_henkan_result("okuriari", "おくr", "贈")
	lib:register_henkan_result("okuriari", "おくr", "遅")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)

	-- OkuRu で送り仮名が確定し、即変換で ▼ 候補選択に入る
	local pre_edit, params = setup_state({ "O", "k", "u", "R", "u" })
	t.assert_equals("henkan", skkelua.phase())
	t.assert_true(vim.startswith(pre_edit, "▼"))

	local list = require("skkelua.lsp")._make_completion_list(params)
	local by_label = {}
	for _, item in ipairs(list.items) do
		by_label[item.label] = item
	end
	-- 全候補が送り仮名付きの完成形で並ぶ
	t.assert_true(by_label["送る"] ~= nil)
	t.assert_true(by_label["贈る"] ~= nil)
	t.assert_true(by_label["遅る"] ~= nil)

	local okuru = by_label["贈る"]
	-- バッファ上の ▼送る にマッチさせる
	t.assert_equals(pre_edit, okuru.filterText)
	t.assert_equals("贈る", okuru.textEdit.newText)
	t.assert_equals(
		{ skkelua = true, midasi = "おくr", word = "贈", type = "okuriari" },
		okuru.data
	)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("completion during okurinasi henkan phase", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)

	-- ▽かんじ からスペースで ▼ 候補選択へ
	local pre_edit, params = setup_state({ "K", "a", "n", "j", "i", " " })
	t.assert_equals("henkan", skkelua.phase())

	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_true(#list.items >= 2)
	local by_label = {}
	for _, item in ipairs(list.items) do
		by_label[item.label] = item
	end
	t.assert_true(by_label["漢字"] ~= nil)
	t.assert_true(by_label["感じ"] ~= nil)
	t.assert_equals(pre_edit, by_label["漢字"].filterText)
	t.assert_equals("okurinasi", by_label["漢字"].data.type)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("okuriari candidate registers with okuriari type", function()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	-- CompleteDone 相当 (data.type = okuriari)
	skkelua.complete_callback("はしr", "走", "okuriari")
	local lib = require("skkelua.store").get_library()
	t.assert_equals({ "走" }, lib:get_henkan_result("okuriari", "はしr"))
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "はしr"))
end)

t.test("insertOnSelect item shape", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true, insertOnSelect = true } })
	skkelua._handle_request("enable", {}, vim_status)

	-- かなのみの pre-edit (▽かんじ): 選択即挿入形式
	local params = setup_henkan_state()
	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_true(#list.items > 0)
	local kanji
	for _, item in ipairs(list.items) do
		if item.label == "漢字" then
			kanji = item
		end
	end
	-- filterText 無し + PlainText + newText 素のまま = 選択で word が挿入される
	t.assert_equals(nil, kanji.filterText)
	t.assert_equals(vim.lsp.protocol.InsertTextFormat.PlainText, kanji.insertTextFormat)
	t.assert_equals("漢字", kanji.textEdit.newText)
	vim.cmd.bwipeout({ bang = true })

	-- ASCII を含む pre-edit (▽おく*r): フィルタを通すため label に
	-- pre-edit を前置し、表示用の display を data に持つ
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "おくr", "送")
	local _, params2 = (function()
		local pre_edit, p = nil, nil
		require("skkelua.store").init_context()
		local sk = require("skkelua")
		for _, k in ipairs({ "O", "k", "u", "R" }) do
			sk._handle_request("handleKey", { key = { k } }, {
				mode = "",
				prevInput = require("skkelua.store").get_context():to_string(),
				completeInfo = {},
				completeType = "",
			})
		end
		pre_edit = sk.get_pre_edit()
		vim.cmd.enew({ bang = true })
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { pre_edit })
		vim.api.nvim_win_set_cursor(0, { 1, #pre_edit })
		p = { position = { line = 0, character = #pre_edit } }
		return pre_edit, p
	end)()
	local list2 = require("skkelua.lsp")._make_completion_list(params2)
	t.assert_true(#list2.items > 0)
	local okuri_item
	for _, item in ipairs(list2.items) do
		if item.data.display == "送り" then
			okuri_item = item
		end
	end
	t.assert_true(okuri_item ~= nil)
	t.assert_equals("▽おく*r送り", okuri_item.label)
	t.assert_equals(nil, okuri_item.filterText)
	t.assert_equals(vim.lsp.protocol.InsertTextFormat.PlainText, okuri_item.insertTextFormat)
	t.assert_equals("送り", okuri_item.textEdit.newText)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("deferOkuri keeps okuriari pre-edit and marks auto-select", function()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "おくr", "送")
	lib:register_henkan_result("okuriari", "おくr", "贈")
	skkelua.config({
		completion = { enabled = true, insertOnSelect = true, deferOkuri = true },
	})
	skkelua._handle_request("enable", {}, vim_status)

	-- OkuRu: 送り仮名確定でも henkan へ行かず ▽おく*る のまま
	local pre_edit, params = setup_state({ "O", "k", "u", "R", "u" })
	t.assert_equals("▽おく*る", pre_edit)
	t.assert_equals("input:okuriari", skkelua.phase())

	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_true(#list.items > 0)
	-- ASCII 無しなので素の insertOnSelect 形式
	-- (「贈」の方が後に登録されているため rank 順で先頭に来る)
	local first = list.items[1]
	t.assert_equals("贈る", first.textEdit.newText)
	t.assert_equals(nil, first.filterText)
	-- auto-select 応答では completeopt から noselect が外れる
	local copt = vim.api.nvim_get_option_value("completeopt", { buf = 0 })
	t.assert_true(not copt:find("noselect"), "noselect should be dropped for auto-select")
	vim.cmd.bwipeout({ bang = true })
end)

t.test("ranked candidate sorts first", function()
	setup_library()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	-- 「感じ」を使った実績を付ける
	skkelua.complete_callback("かんじ", "感じ")

	local params = setup_henkan_state()
	local list = require("skkelua.lsp")._make_completion_list(params)
	t.assert_true(#list.items >= 2)
	t.assert_equals("感じ", list.items[1].label)
	-- 内部ソートキーは応答に残さない
	t.assert_equals(nil, list.items[1]._sort_rank)
	vim.cmd.bwipeout({ bang = true })
end)

t.test("CompleteDone registers only on accept", function()
	local skkelua = require("skkelua")
	skkelua.config({ completion = { enabled = true } })
	skkelua._handle_request("enable", {}, vim_status)
	local lib = require("skkelua.store").get_library()
	local lsp_mod = require("skkelua.lsp")

	local function completed_item(word)
		return {
			user_data = {
				nvim = {
					lsp = {
						completion_item = {
							data = { skkelua = true, midasi = "むこう", word = word, type = "okurinasi" },
						},
					},
				},
			},
		}
	end

	-- <Esc> などによる discard / cancel では登録しない
	lsp_mod._on_complete_done("discard", completed_item("無香"))
	lsp_mod._on_complete_done("cancel", completed_item("無効"))
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "むこう"))

	-- accept (<C-y> 等) では登録する
	lsp_mod._on_complete_done("accept", completed_item("向こう"))
	t.assert_equals({ "向こう" }, lib:get_henkan_result("okurinasi", "むこう"))

	-- reason が取れない環境では従来通り登録する
	lsp_mod._on_complete_done(nil, completed_item("尨"))
	t.assert_equals({ "尨", "向こう" }, lib:get_henkan_result("okurinasi", "むこう"))
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
