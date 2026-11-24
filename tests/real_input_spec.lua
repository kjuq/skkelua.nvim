-- 実際のキー入力を通したテスト
--
-- Note: headless (-l) の本体は insert モードに入れないため、--embed の子
--       Neovim を起動し、nvim_input でキーを送って振る舞いを確認する

local t = require("tests.helper")

local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))

--- 子 Neovim で skkelua を読み込み、<C-j> を toggle に割り当てる
---@param indicator table indicator の設定
---@return integer channel
local function spawn(indicator)
	local ch = vim.fn.jobstart({ "nvim", "--clean", "--embed", "--headless" }, { rpc = true })
	vim.rpcrequest(
		ch,
		"nvim_exec_lua",
		[[
		local root, indicator = ...
		vim.opt.runtimepath:prepend(root)
		vim.cmd("runtime! plugin/skkelua.lua")
		require("skkelua").config({ sources = {}, userDictionary = "", completionRankFile = "", indicator = indicator })
		vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkelua-toggle)")
		]],
		{ root, indicator }
	)
	return ch
end

---@param ch integer
---@param code string
local function eval(ch, code)
	return vim.rpcrequest(ch, "nvim_exec_lua", code, {})
end

--- キーを送り、子のモードが mode になるまで待つ
---@param ch integer
---@param keys string
---@param mode string
local function input(ch, keys, mode)
	vim.rpcrequest(ch, "nvim_input", keys)
	t.assert_true(vim.wait(1000, function()
		return vim.rpcrequest(ch, "nvim_get_mode").mode == mode
	end, 10), ("mode did not become %s after %s"):format(mode, keys))
end

--- 子 Neovim を起動して fn を実行し、成否にかかわらず終了させる
---@param indicator table
---@param fn fun(ch: integer)
local function with_child(indicator, fn)
	local ch = spawn(indicator)
	local ok, err = pcall(fn, ch)
	vim.fn.jobstop(ch)
	if not ok then
		error(err, 0)
	end
end

--- 子の値が expected になるまで待ち、最後に観測した値を返す
local function wait_for(ch, code, expected)
	local actual
	vim.wait(500, function()
		actual = eval(ch, code)
		return actual == expected
	end, 10)
	return actual
end

t.test("CTRL-C disables skkelua without waiting for another key", function()
	-- インジケータの描画がイベントループを動かして結果を隠さないよう切る
	with_child({ enabled = false }, function(ch)
		input(ch, "i", "i")
		input(ch, "<C-j>", "i")
		t.assert_equals(true, eval(ch, "return require('skkelua').is_enabled()"))
		-- RPC の処理自体がイベントループを動かして SafeState を誘発するので、
		-- <C-c> の後は RPC を送らずに待ち、最初の 1 回だけで観測する
		vim.rpcrequest(ch, "nvim_input", "<C-c>")
		vim.wait(300)
		t.assert_equals(
			{ mode = "n", enabled = false },
			eval(ch, "return { mode = vim.api.nvim_get_mode().mode, enabled = require('skkelua').is_enabled() }")
		)
	end)
end)

t.test("CTRL-C closes the indicator", function()
	with_child({ fadeOutMs = 0, alwaysShown = false }, function(ch)
		local count_floats = [[
			return #vim.tbl_filter(function(w)
				return vim.api.nvim_win_get_config(w).relative ~= ""
			end, vim.api.nvim_list_wins())
		]]
		input(ch, "i", "i")
		input(ch, "<C-j>", "i")
		t.assert_equals(1, wait_for(ch, count_floats, 1))
		input(ch, "<C-c>", "n")
		t.assert_equals(0, wait_for(ch, count_floats, 0))
	end)
end)
