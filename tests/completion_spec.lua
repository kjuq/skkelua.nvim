-- 補完 UI が挿入した候補の扱いのテスト
--
-- skkelua は補完 UI に問い合わせず、共有クライアント (lsp.start) へ返した
-- 候補が pre-edit の位置に挿入されているかをバッファから判定する

local t = require("tests.helper")

local function tc(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

local function feed(keys)
	vim.fn.feedkeys(tc(keys), "tx")
end

--- 補完 UI を模したマッピングを張る (laser.nvim と同じ操作をする)。
--- <C-t>: 共有クライアントに補完を要求する
--- <C-n>: 次の項目を、noremap の <BS> と項目の文字列を feedkeys して挿入する
--- <F2>: 選択中の項目を確定する (項目の command をクライアントが実行する)
--- <F3>: 選択をやめて、要求時の入力に戻す
---@param client vim.lsp.Client
local function map_fake_ui(client)
	local items, index, typed = {}, 0, ""
	local function replace_with(text)
		local current = index > 0 and items[index].textEdit.newText or typed
		vim.api.nvim_feedkeys(tc(("<BS>"):rep(vim.fn.strcharlen(current)) .. text), "in", false)
	end
	vim.keymap.set("i", "<C-t>", function()
		local pos = vim.api.nvim_win_get_cursor(0)
		local result
		client:request("textDocument/completion", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = pos[1] - 1, character = pos[2] },
		}, function(_, res)
			result = res or { items = {} }
		end, 0)
		t.assert_true(vim.wait(1000, function()
			return result ~= nil
		end))
		items, index = result.items, 0
		local range = vim.tbl_get(items, 1, "textEdit", "range")
		typed = range and vim.api.nvim_get_current_line():sub(range.start.character + 1, pos[2]) or ""
	end, { buffer = true })
	vim.keymap.set("i", "<C-n>", function()
		if index < #items then
			replace_with(items[index + 1].textEdit.newText)
			index = index + 1
		end
	end, { buffer = true })
	vim.keymap.set("i", "<F2>", function()
		local item = items[index]
		items, index = {}, 0
		if item then
			local done = false
			client:exec_cmd(item.command, { bufnr = 0 }, function()
				done = true
			end)
			t.assert_true(vim.wait(1000, function()
				return done
			end))
		end
	end, { buffer = true })
	vim.keymap.set("i", "<F3>", function()
		if index > 0 then
			replace_with(typed)
		end
		items, index = {}, 0
	end, { buffer = true })
end

--- 補完 UI を模したマッピングを張ったバッファで fn を実行する。
--- skkelua.complete_callback (辞書学習) の呼び出しを記録して返す
---@param fn fun()
---@return table[] learned
local function with_fake_ui(fn)
	require("skkelua.store").get_library():register_henkan_result("okurinasi", "かんじ", "漢字")
	local skkelua = require("skkelua")
	local learned = {}
	local complete_callback = skkelua.complete_callback
	skkelua.complete_callback = function(...)
		learned[#learned + 1] = { ... }
		return complete_callback(...)
	end
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	vim.fn.setreg("q", "")
	local ok, err = pcall(function()
		local client = assert(vim.lsp.get_client_by_id(require("skkelua.lsp").start()))
		t.assert_true(vim.wait(1000, function()
			return client.initialized
		end))
		map_fake_ui(client)
		fn()
	end)
	skkelua.complete_callback = complete_callback
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
	return learned
end

t.test("<C-y> commits the candidate a completion UI inserted", function()
	local learned = with_fake_ui(function()
		feed("iJKanji<C-t><C-n><C-y>")
		t.assert_equals({ "漢字" }, vim.fn.getline(1, "$"))
		t.assert_equals("input", require("skkelua.store").status.phase)
	end)
	t.assert_equals({ { "かんじ", "漢字", "okurinasi" } }, learned)
end)

t.test("typing after a completion UI inserted a candidate commits it first", function()
	local learned = with_fake_ui(function()
		feed("iJKanji<C-t><C-n>a")
		t.assert_equals({ "漢字あ" }, vim.fn.getline(1, "$"))
	end)
	t.assert_equals({ { "かんじ", "漢字", "okurinasi" } }, learned)
end)

t.test("<C-w> deletes the candidate a completion UI inserted", function()
	local learned = with_fake_ui(function()
		-- native の <C-w> なら、同じ挿入で入れた前の 漢 も同じ単語として消える
		vim.cmd("inoremap <buffer> <F4> 漢")
		feed("iJ<F4>Kanji<C-t><C-n><C-w>")
		t.assert_equals({ "漢" }, vim.fn.getline(1, "$"))
	end)
	t.assert_equals({}, learned)
end)

t.test("a candidate the completion UI confirmed is learned once", function()
	local learned = with_fake_ui(function()
		feed("iJKanji<C-t><C-n><F2>a")
		t.assert_equals({ "漢字あ" }, vim.fn.getline(1, "$"))
	end)
	t.assert_equals({ { "かんじ", "漢字", "okurinasi" } }, learned)
end)

t.test("the pre-edit the completion UI restored is still converted", function()
	local learned = with_fake_ui(function()
		feed("iJKanji<C-t><C-n><F3><C-y>")
		t.assert_equals({ "かんじ" }, vim.fn.getline(1, "$"))
	end)
	t.assert_equals({}, learned)
end)

t.test("replaying a macro inserts the candidate without the completion UI", function()
	with_fake_ui(function()
		feed("qqiJKanji<C-t><C-n><C-y><CR><Esc>q")
		t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
		feed("@q")
		t.assert_equals({ "漢字", "漢字", "" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("items from other sources are not treated as skkelua candidates", function()
	local list = require("skkelua.lsp.list")
	t.assert_equals(nil, list.item_data({ data = { other = true } }))
	t.assert_equals(nil, list.item_data(nil))
	t.assert_equals({ skkelua = true }, list.item_data({ data = { skkelua = true } }))
end)
