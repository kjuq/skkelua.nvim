-- 辞書登録プロンプト (フロート版) のテスト
--
-- Note: 実バッファを使う復元フローは feedkeys で駆動し、確定だけは
--       headless では <CR> の代わりにテスト用 API の _confirm で駆動する。

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "tx")
end

--- 辞書登録の復元処理は pre-edit が実バッファ上にあることを前提にするため、
--- 低レベルの handle API ではなく実際の insert バッファを用意する。
local function prepare_buffer()
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	return vim.api.nvim_get_current_buf()
end

local function cleanup_buffer(buf, prompt)
	prompt._close()
	vim.wait(100)
	vim.cmd("stopinsert")
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

t.test("register prompt opens a float prompt buffer with skkelua enabled", function()
	local prompt = require("skkelua.register_prompt")
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] てすと",
			on_confirm = function() end,
			on_cancel = function() end,
		})
		local cur = prompt._current()
		t.assert_true(cur ~= nil)
		t.assert_equals("prompt", vim.bo[cur.buf].buftype)
		t.assert_true(vim.api.nvim_win_is_valid(cur.win))
		t.assert_equals(cur.win, vim.api.nvim_get_current_win())
		-- プロンプトバッファで skkelua が有効になっている
		t.assert_true(require("skkelua").is_enabled())
	end)
	prompt._close()
	t.assert_equals(nil, prompt._current())
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("register prompt gets the LSP client of the buffer it was opened from", function()
	local prompt = require("skkelua.register_prompt")
	local lsp = require("skkelua.lsp")
	local opts = { title = "[辞書登録] てすと", on_confirm = function() end, on_cancel = function() end }
	-- 前のテストのプロンプトのウィンドウ破棄 (schedule) を済ませてから作る
	vim.wait(100)
	local buf = prepare_buffer()
	local ok, err = pcall(function()
		-- 補完 UI のクライアントが無いバッファからは、プロンプトにも付けない
		prompt.open(opts)
		t.assert_equals(nil, lsp.client(prompt._current().buf))
		prompt._close()
		-- ウィンドウの破棄は schedule される
		t.assert_true(vim.wait(1000, function()
			return vim.api.nvim_get_current_buf() == buf
		end))

		local client_id = lsp.start(buf)
		prompt.open(opts)
		local outer = prompt._current().buf
		t.assert_equals(client_id, (lsp.client(outer) or {}).id)
		-- ネストしたプロンプトは外側のプロンプトから引き継ぐ
		prompt.open(opts)
		t.assert_equals(client_id, (lsp.client(prompt._current().buf) or {}).id)
	end)
	cleanup_buffer(buf, prompt)
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("external window close triggers on_cancel", function()
	local prompt = require("skkelua.register_prompt")
	local cancelled = false
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] てすと",
			on_confirm = function() end,
			on_cancel = function()
				cancelled = true
			end,
		})
		local cur = prompt._current()
		t.assert_true(cur ~= nil)
		-- fclose! などの外部クローズを模擬する
		vim.api.nvim_win_close(cur.win, true)
		vim.wait(200, function()
			return cancelled
		end, 10)
		t.assert_true(cancelled, "on_cancel should be called on external close")
		t.assert_equals(nil, prompt._current())
	end)
	prompt._close()
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("external close restores henkan input state", function()
	local skkelua = require("skkelua")
	local prompt = require("skkelua.register_prompt")
	local store = require("skkelua.store")
	local scratch = prepare_buffer()

	local ok, err = pcall(function()
		feed("iJNunu ")
		vim.wait(200, function()
			return prompt._current() ~= nil
		end, 10)
		local cur = prompt._current()
		t.assert_true(cur ~= nil, "float prompt should open")

		-- fclose! などの外部クローズを模擬する
		vim.api.nvim_win_close(cur.win, true)
		vim.wait(200, function()
			return prompt._current() == nil and store.get_context().state.type == "input"
		end, 10)

		-- 変換入力状態 (▽ぬぬ) が生きた状態で復元されている
		local context = store.get_context()
		t.assert_equals("input", context.state.type)
		t.assert_equals("okurinasi", context.state.mode)
		t.assert_equals("ぬぬ", context.state.henkanFeed)
		t.assert_equals("▽ぬぬ", context:to_string())
		t.assert_true(skkelua.is_enabled(), "skkelua should be re-enabled")
		-- 補完 (make_completion_list) が参照する公開ステータスも復元されている
		t.assert_equals("input:okurinasi", skkelua.phase())
		t.assert_equals("ぬぬ", store.status.henkanFeed)
		t.assert_equals({ "▽ぬぬ" }, vim.api.nvim_buf_get_lines(scratch, 0, -1, false))
	end)
	cleanup_buffer(scratch, prompt)
	skkelua._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("register_word opens the float outside cmdline", function()
	local skkelua = require("skkelua")
	local prompt = require("skkelua.register_prompt")
	skkelua._handle_request("enable", {}, vim_status)

	-- 辞書に無い読みで変換開始 -> 候補ゼロで register_word が呼ばれる
	local ok, err = pcall(function()
		for _, k in ipairs({ "N", "u", "n", "u" }) do
			skkelua._handle_request("handleKey", { key = { k } }, {
				mode = "",
				prevInput = require("skkelua.store").get_context():to_string(),
				completeInfo = {},
				completeType = "",
			})
		end
		skkelua._handle_request(
			"handleKey",
			{ ["function"] = "henkanFirst", key = { "" } },
			{ mode = "", prevInput = "▽ぬぬ", completeInfo = {}, completeType = "" }
		)
		-- フロートは schedule で開く
		vim.wait(200, function()
			return prompt._current() ~= nil
		end, 10)
		local cur = prompt._current()
		t.assert_true(cur ~= nil, "float prompt should open")
	end)
	prompt._close()
	skkelua._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("nested open keeps the outer prompt alive", function()
	local prompt = require("skkelua.register_prompt")
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] そと",
			on_confirm = function() end,
			on_cancel = function() end,
		})
		local outer = prompt._current()
		-- open はフロートへ入るので、そのまま開くとネストになる
		prompt.open({
			title = "[辞書登録] なか",
			on_confirm = function() end,
			on_cancel = function() end,
		})
		local inner = prompt._current()
		t.assert_true(inner.win ~= outer.win, "nested prompt should be a new window")
		t.assert_equals(2, #prompt._stack())
		t.assert_true(vim.api.nvim_win_is_valid(outer.win), "outer should stay open")
		-- 内側は外側の右下へずらしたカスケード配置
		local cfg = vim.api.nvim_win_get_config(inner.win)
		t.assert_equals("win", cfg.relative)
		t.assert_equals(outer.win, cfg.win)
		t.assert_equals(2, cfg.row)
		t.assert_equals(2, cfg.col)
		t.assert_equals(51, cfg.zindex)
	end)
	prompt._close()
	t.assert_equals(nil, prompt._current())
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("closing the inner prompt returns to the outer", function()
	local prompt = require("skkelua.register_prompt")
	local outer_cancelled, inner_cancelled = false, false
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] そと",
			on_confirm = function() end,
			on_cancel = function()
				outer_cancelled = true
			end,
		})
		local outer = prompt._current()
		prompt.open({
			title = "[辞書登録] なか",
			on_confirm = function() end,
			on_cancel = function()
				inner_cancelled = true
			end,
		})
		local inner = prompt._current()

		vim.api.nvim_win_close(inner.win, true)
		vim.wait(200, function()
			return inner_cancelled
		end, 10)
		t.assert_true(inner_cancelled, "inner on_cancel should be called")
		t.assert_true(not outer_cancelled, "outer should not be cancelled")
		t.assert_equals(1, #prompt._stack())
		t.assert_equals(outer.win, prompt._current().win)
		t.assert_true(vim.api.nvim_win_is_valid(outer.win))
	end)
	prompt._close()
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("external close of the outer prompt cascades", function()
	local prompt = require("skkelua.register_prompt")
	local outer_cancelled, inner_cancelled = false, false
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] そと",
			on_confirm = function() end,
			on_cancel = function()
				outer_cancelled = true
			end,
		})
		local outer = prompt._current()
		prompt.open({
			title = "[辞書登録] なか",
			on_confirm = function() end,
			on_cancel = function()
				inner_cancelled = true
			end,
		})
		local inner = prompt._current()

		vim.api.nvim_win_close(outer.win, true)
		vim.wait(200, function()
			return outer_cancelled
		end, 10)
		t.assert_true(outer_cancelled, "outer on_cancel should be called")
		-- 内側は復帰先 (外側プロンプト) ごと失われるため silent discard
		t.assert_true(not inner_cancelled, "inner should be discarded silently")
		t.assert_true(not vim.api.nvim_win_is_valid(inner.win))
		t.assert_equals(nil, prompt._current())
	end)
	prompt._close()
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("re-open from outside the prompt replaces the stack", function()
	local prompt = require("skkelua.register_prompt")
	local orig_win = vim.api.nvim_get_current_win()
	local old_cancelled = false
	local ok, err = pcall(function()
		prompt.open({
			title = "[辞書登録] ふるい",
			on_confirm = function() end,
			on_cancel = function()
				old_cancelled = true
			end,
		})
		local old = prompt._current()
		-- プロンプト外へ戻ってから開き直すとネストではなく置き換えになる
		vim.api.nvim_set_current_win(orig_win)
		prompt.open({
			title = "[辞書登録] あたらしい",
			on_confirm = function() end,
			on_cancel = function() end,
		})
		t.assert_equals(1, #prompt._stack())
		t.assert_true(prompt._current().win ~= old.win)
		-- ウィンドウの破棄は schedule されるため次のティックまで待つ
		vim.wait(200, function()
			return not vim.api.nvim_win_is_valid(old.win)
		end, 10)
		t.assert_true(not vim.api.nvim_win_is_valid(old.win))
		vim.wait(100)
		t.assert_true(not old_cancelled, "replaced prompt should be discarded silently")
	end)
	prompt._close()
	require("skkelua")._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("register_word nests inside the prompt", function()
	local skkelua = require("skkelua")
	local prompt = require("skkelua.register_prompt")
	local store = require("skkelua.store")
	local scratch = prepare_buffer()

	local ok, err = pcall(function()
		-- 辞書に無い読み (▽ぬぬ) で外側のプロンプトを開く
		feed("iJNunu ")
		vim.wait(200, function()
			return prompt._current() ~= nil
		end, 10)
		local outer = prompt._current()
		t.assert_true(outer ~= nil, "outer prompt should open")

		-- プロンプト内でさらに辞書に無い読み (▽ねね) を変換するとネストする
		feed(vim.fn.mode() == "i" and "Nene " or "aNene ")
		vim.wait(200, function()
			local cur = prompt._current()
			return cur ~= nil and cur.win ~= outer.win
		end, 10)
		local inner = prompt._current()
		t.assert_true(inner ~= nil and inner.win ~= outer.win, "nested prompt should open")
		t.assert_true(vim.api.nvim_win_is_valid(outer.win), "outer should stay open")

		-- 内側のキャンセルで外側プロンプトへ ▽ねね が復元される
		vim.api.nvim_win_close(inner.win, true)
		vim.wait(200, function()
			return prompt._current() ~= nil
				and prompt._current().win == outer.win
				and store.get_context().state.type == "input"
		end, 10)
		t.assert_equals(outer.win, prompt._current().win)
		t.assert_equals(outer.win, vim.api.nvim_get_current_win())
		local context = store.get_context()
		t.assert_equals("input", context.state.type)
		t.assert_equals("ねね", context.state.henkanFeed)
		t.assert_equals("▽ねね", context:to_string())
		t.assert_equals({ "> ▽ねね" }, vim.api.nvim_buf_get_lines(outer.buf, 0, -1, false))
	end)
	cleanup_buffer(scratch, prompt)
	skkelua._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("confirming the nested prompt registers to the dictionary", function()
	local skkelua = require("skkelua")
	local prompt = require("skkelua.register_prompt")
	local store = require("skkelua.store")
	local scratch = prepare_buffer()

	local ok, err = pcall(function()
		feed("iJNunu ")
		vim.wait(200, function()
			return prompt._current() ~= nil
		end, 10)
		local outer = prompt._current()
		t.assert_true(outer ~= nil, "outer prompt should open")

		feed(vim.fn.mode() == "i" and "Nene " or "aNene ")
		vim.wait(200, function()
			local cur = prompt._current()
			return cur ~= nil and cur.win ~= outer.win
		end, 10)
		t.assert_true(prompt._current().win ~= outer.win, "nested prompt should open")

		-- ネスト側を確定すると辞書登録され、外側プロンプトへ復帰する
		-- バッファ上の pre-edit も登録候補へ置換される
		prompt._confirm("根")
		vim.wait(200, function()
			return #store.get_library():get_henkan_result("okurinasi", "ねね") > 0
		end, 10)
		t.assert_equals({ "根" }, store.get_library():get_henkan_result("okurinasi", "ねね"))
		t.assert_equals(1, #prompt._stack())
		t.assert_equals(outer.win, prompt._current().win)
		t.assert_equals(outer.win, vim.api.nvim_get_current_win())
		t.assert_equals({ "> 根" }, vim.api.nvim_buf_get_lines(outer.buf, 0, -1, false))
	end)
	cleanup_buffer(scratch, prompt)
	skkelua._handle_request("disable", {}, vim_status)
	if not ok then
		error(err, 0)
	end
end)

t.test("register_word falls back to cmdline input in cmdline mode", function()
	local skkelua = require("skkelua")
	local prompt = require("skkelua.register_prompt")
	skkelua._handle_request("enable", {}, vim_status)
	local context = require("skkelua.store").get_context()
	context.vimMode = "c"
	context.state.type = "henkan"
	context.state.mode = "okurinasi"
	context.state.henkanFeed = "ぬぬ"
	context.state.word = "ぬぬ"
	context.state.candidates = {}
	context.state.candidateIndex = 0

	-- input() は headless では入力待ちでブロックするため stub する
	-- (空文字 = キャンセル扱い)
	local orig_input = vim.fn.input
	rawset(vim.fn, "input", function()
		return ""
	end)
	local ok, registered = pcall(require("skkelua.function.dictionary").register_word, context)
	rawset(vim.fn, "input", orig_input)
	if not ok then
		error(registered, 0)
	end
	t.assert_equals(false, registered)
	t.assert_equals(nil, prompt._current(), "float should not open in cmdline")
	skkelua._handle_request("disable", {}, vim_status)
end)
