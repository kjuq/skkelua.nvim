-- 辞書登録プロンプト (フロート版) のテスト
--
-- Note: 確定・キャンセルのフルフロー (insert モード遷移 + feedkeys) は
--       headless では検証できないため E2E に任せ、ここでは
--       フロートの開閉と経路の分岐を確認する

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

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
	skkelua._handle_request("enable", {}, vim_status)

	local ok, err = pcall(function()
		for _, k in ipairs({ "N", "u", "n", "u" }) do
			skkelua._handle_request("handleKey", { key = { k } }, {
				mode = "",
				prevInput = store.get_context():to_string(),
				completeInfo = {},
				completeType = "",
			})
		end
		skkelua._handle_request(
			"handleKey",
			{ ["function"] = "henkanFirst", key = { "" } },
			{ mode = "", prevInput = "▽ぬぬ", completeInfo = {}, completeType = "" }
		)
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
	end)
	prompt._close()
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
