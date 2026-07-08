-- 内蔵モードインジケータのテスト
--
-- Note: headless (-l) では insert モードに実際に入れないため、
--       autocmd 連動 (InsertEnter/mode-changed) はユニットレベルで検証し、
--       open/detect/設定反映のロジックを直接呼び出しで確認する

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

--- schedule 済みのコールバックを消化する
local function drain()
	vim.wait(30, function()
		return false
	end, 5)
end

--- インジケータのウィンドウのテキストを返す (無ければ nil)
local function indicator_text()
	local indicator = require("skkelua.indicator")._instance()
	if not indicator or #indicator.winid == 0 then
		return nil
	end
	local winid = indicator.winid[1]
	if not vim.api.nvim_win_is_valid(winid) then
		return nil
	end
	local buf = vim.api.nvim_win_get_buf(winid)
	return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end

local function attach()
	require("skkelua.indicator").attach()
	return require("skkelua.indicator")._instance()
end

t.test("indicator shows eiji when disabled and hira after enable", function()
	local skkelua = require("skkelua")
	local instance = attach()
	t.assert_true(instance ~= nil)

	-- 無効時は英字
	instance:open()
	t.assert_equals("英字", indicator_text())

	-- 有効化するとモード検出が hira になる
	skkelua._handle_request("enable", {}, vim_status)
	instance:close()
	drain()
	t.assert_equals(nil, indicator_text())
	instance:open()
	t.assert_equals("ひら", indicator_text())
	t.assert_equals("ひら", instance:detect().text)
end)

t.test("indicator follows mode changes", function()
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local instance = attach()
	skkelua._handle_request("enable", {}, vim_status)
	require("skkelua.function.mode").katakana(store.get_context())
	t.assert_equals("カタ", instance:detect().text)
	require("skkelua.function.mode").hankatakana(store.get_context())
	t.assert_equals("半ｶﾀ", instance:detect().text)
	require("skkelua.function.mode").zenkaku(store.get_context())
	t.assert_equals("全英", instance:detect().text)
end)

t.test("update is skipped outside insert mode", function()
	local skkelua = require("skkelua")
	local instance = attach()
	-- attach 直後に開いたウィンドウ (InsertEnter 相当) を閉じておく
	instance:close()
	drain()
	skkelua._handle_request("enable", {}, vim_status)
	-- normal モードでは update は何もしない (ウィンドウは開かない)
	instance:update("mode-changed")
	drain()
	t.assert_equals(nil, indicator_text())
end)

t.test("indicator closes on disable-post when alwaysShown = false", function()
	local skkelua = require("skkelua")
	skkelua.config({ indicator = { alwaysShown = false, fadeOutMs = 0 } })
	local instance = attach()

	-- 無効時は is_disabled で開かない
	instance:open()
	t.assert_equals(nil, indicator_text())

	-- 有効化すると開ける
	skkelua._handle_request("enable", {}, vim_status)
	instance:open()
	t.assert_equals("ひら", indicator_text())

	-- disable-post 相当の更新で閉じる (insert 外でも close パスは通る)
	skkelua._handle_request("disable", {}, vim_status)
	instance:close()
	drain()
	t.assert_equals(nil, indicator_text())
end)

t.test("indicator does not attach when disabled by config", function()
	require("skkelua").config({ indicator = { enabled = false } })
	require("skkelua.indicator").attach()
	t.assert_equals(nil, require("skkelua.indicator")._instance())
end)

t.test("indicator text and highlight are configurable", function()
	local skkelua = require("skkelua")
	skkelua.config({ indicator = { hiraText = "あ", hiraHlName = "MyHira" } })
	local instance = attach()
	skkelua._handle_request("enable", {}, vim_status)
	local mode = instance:detect()
	t.assert_equals("あ", mode.text)
	t.assert_equals("MyHira", mode.hl_name)
	-- ハイライトグループが定義される
	t.assert_true(not vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "MyHira" })))

	-- config() を後から呼ぶと refresh で反映される
	skkelua.config({ indicator = { hiraText = "ひ" } })
	t.assert_equals("ひ", instance:detect().text)
end)

t.test("fade out timer closes the window", function()
	local skkelua = require("skkelua")
	skkelua.config({ indicator = { fadeOutMs = 20 } })
	local instance = attach()
	instance:close()
	drain()
	skkelua._handle_request("enable", {}, vim_status)
	instance:open()
	t.assert_equals("ひら", indicator_text())
	-- fadeOutMs 経過後に閉じる
	vim.wait(500, function()
		return indicator_text() == nil
	end, 10)
	t.assert_equals(nil, indicator_text())
end)
