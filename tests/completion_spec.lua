-- 外部の補完 UI アダプター (completion.set_adapter) のテスト

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

--- 現在の補完 UI の状態を渡して handleKey を呼ぶ
---@param key string
local function handle_key(key)
	local skkelua = require("skkelua")
	local status = skkelua.vim_status()
	return skkelua._handle_request("handleKey", { key = { key } }, {
		mode = "",
		prevInput = require("skkelua.store").get_context():to_string(),
		completeInfo = status.completeInfo,
		completeType = status.completeType,
	})
end

--- ▽かんじ の変換入力状態を作る
local function setup_henkan_input()
	require("skkelua")._handle_request("enable", {}, vim_status)
	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		handle_key(k)
	end
	t.assert_equals("▽かんじ", require("skkelua").get_pre_edit())
end

--- 選択中の候補だけを返すアダプター
---@param item table CompletionItem
local function adapter_selecting(item)
	return {
		selected = function()
			return item
		end,
		confirm = function()
			return "external-confirm"
		end,
	}
end

t.test("<C-y> delegates confirmation to the adapter", function()
	setup_henkan_input()
	require("skkelua.completion").set_adapter(adapter_selecting({ data = { skkelua = true } }))
	local ret = handle_key("<c-y>")
	t.assert_equals("external-confirm", ret.result)
	t.assert_equals("", require("skkelua").get_pre_edit())
end)

t.test("<C-y> on a selected [辞書登録] item keeps the pre-edit", function()
	setup_henkan_input()
	require("skkelua.completion").set_adapter(adapter_selecting({ data = { skkelua = true, register = true } }))
	local ret = handle_key("<c-y>")
	t.assert_equals("external-confirm", ret.result)
	t.assert_equals("▽かんじ", require("skkelua").get_pre_edit())
end)

t.test("<C-y> without a selection is not handed to the adapter", function()
	setup_henkan_input()
	require("skkelua.completion").set_adapter({
		selected = function()
			return nil
		end,
		confirm = function()
			return "external-confirm"
		end,
	})
	local ret = handle_key("<c-y>")
	t.assert_true(ret.result ~= "external-confirm")
end)

t.test("an explicit adapter takes precedence over detected UIs", function()
	local saved = package.loaded["cmp"]
	package.loaded["cmp"] = {
		visible = function()
			return true
		end,
		get_active_entry = function()
			return {}
		end,
	}
	require("skkelua.completion").set_adapter(adapter_selecting({}))
	local confirm = require("skkelua.completion").confirm()
	package.loaded["cmp"] = saved
	t.assert_equals("external-confirm", confirm)
end)

t.test("a restored pre-edit is announced to completion UIs through a User event", function()
	local fired = 0
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "skkelua-pre-edit-restored",
		callback = function()
			fired = fired + 1
		end,
	})
	require("skkelua.lsp").pre_edit_restored()
	vim.api.nvim_del_autocmd(id)
	t.assert_equals(1, fired)
end)

t.test("selected_word finds the selected candidate's text before the cursor", function()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "漢字 " })
	-- Normal モードでもカーソル前が "漢字" になるよう、後ろに文字を置く
	vim.api.nvim_win_set_cursor(0, { 1, #"漢字" })
	local item = { data = { skkelua = true, word = "漢字", text = "漢字" } }
	require("skkelua.completion").set_adapter({
		selected = function()
			return item
		end,
		confirm = function()
			return ""
		end,
	})
	local word, data = require("skkelua.lsp").selected_word()
	vim.api.nvim_buf_delete(buf, { force = true })
	t.assert_equals("漢字", word)
	t.assert_equals(item.data, data)
end)

t.test("selected_word ignores a selection that is not inserted yet", function()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "▽かんじ " })
	vim.api.nvim_win_set_cursor(0, { 1, #"▽かんじ" })
	require("skkelua.completion").set_adapter(adapter_selecting({ data = { skkelua = true, text = "漢字" } }))
	local word = require("skkelua.lsp").selected_word()
	vim.api.nvim_buf_delete(buf, { force = true })
	t.assert_equals(nil, word)
end)

t.test("items from other sources are not treated as skkelua candidates", function()
	local completion = require("skkelua.completion")
	t.assert_equals(nil, completion.item_data({ data = { other = true } }))
	t.assert_equals(false, completion.is_register_item({ data = { skkelua = true } }))
	t.assert_equals(true, completion.is_register_item({ data = { skkelua = true, register = true } }))
end)

t.test("an adapter that throws does not break key handling", function()
	require("skkelua.store").get_library():register_henkan_result("okurinasi", "かんじ", "漢字")
	setup_henkan_input()
	require("skkelua.completion").set_adapter({
		selected = function()
			error("boom")
		end,
		confirm = function()
			error("boom")
		end,
	})
	local notify = vim.notify_once
	vim.notify_once = function() end
	local ok, err = pcall(function()
		-- 状態が分からない間はメニュー無しとして扱い、skkelua 自身が処理する
		t.assert_equals({ true, nil }, { require("skkelua.completion").selection() })
		t.assert_equals(nil, require("skkelua.completion").confirm())
		handle_key("<space>")
	end)
	vim.notify_once = notify
	if not ok then
		error(err, 0)
	end
	t.assert_equals("henkan", require("skkelua.store").get_context().state.type)
end)

t.test("adapter results are normalized", function()
	local completion = require("skkelua.completion")
	completion.set_adapter({
		selected = function()
			return "not an item"
		end,
		confirm = function()
			return 1
		end,
	})
	t.assert_equals({ true, nil }, { completion.selection() })
	t.assert_equals(nil, completion.confirm())
	-- data を持てない UI は空の CompletionItem で「選択中」だけ伝えられる
	completion.set_adapter({
		selected = function()
			return {}
		end,
		confirm = function()
			return ""
		end,
	})
	t.assert_equals({ true, {} }, { completion.selection() })
end)

--- pum.vim の関数を差し替えて fn を実行する
--- (autoload 関数は autoload/pum.vim にしか定義できないので一時ディレクトリに置く)
---@param info table pum#complete_info() の戻り値
---@param current table pum#current_item() の戻り値
---@param fn fun()
local function with_pum(info, current, fn)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir .. "/autoload", "p")
	vim.fn.writefile({
		"function! pum#visible() abort",
		"  return v:true",
		"endfunction",
		"function! pum#complete_info(...) abort",
		"  return g:skkelua_test_pum_info",
		"endfunction",
		"function! pum#current_item() abort",
		"  return g:skkelua_test_pum_current",
		"endfunction",
	}, dir .. "/autoload/pum.vim")
	vim.g.skkelua_test_pum_info = info
	vim.g.skkelua_test_pum_current = current
	vim.opt.runtimepath:prepend(dir)
	vim.cmd("runtime autoload/pum.vim")
	local ok, err = pcall(fn)
	vim.opt.runtimepath:remove(dir)
	vim.cmd("delfunction pum#visible | delfunction pum#complete_info | delfunction pum#current_item")
	vim.fn.delete(dir, "rf")
	if not ok then
		error(err, 0)
	end
end

t.test("pum.vim reports the selected LSP item", function()
	local lspitem = vim.json.encode({ label = "漢字", data = { skkelua = true } })
	with_pum(
		{ pum_visible = true, selected = 1, inserted = "漢字" },
		{ user_data = { lspitem = lspitem } },
		function()
			local external, item = require("skkelua.completion").selection()
			t.assert_equals(true, external)
			t.assert_equals({ label = "漢字", data = { skkelua = true } }, item)
		end
	)
end)

t.test("pum.vim has no selection while nothing is selected", function()
	with_pum({ pum_visible = true, selected = -1 }, {}, function()
		t.assert_equals({ true, nil }, { require("skkelua.completion").selection() })
	end)
end)

t.test("nvim-cmp reports the active entry's completion item", function()
	local saved = package.loaded["cmp"]
	local item = { label = "漢字", data = { skkelua = true, register = true } }
	package.loaded["cmp"] = {
		visible = function()
			return true
		end,
		get_active_entry = function()
			return {
				get_completion_item = function()
					return item
				end,
			}
		end,
	}
	local ok, err = pcall(function()
		local external, selected = require("skkelua.completion").selection()
		t.assert_equals(true, external)
		t.assert_equals(item, selected)
		t.assert_equals(true, require("skkelua.completion").is_register_item(selected))
	end)
	package.loaded["cmp"] = saved
	if not ok then
		error(err, 0)
	end
end)
