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
