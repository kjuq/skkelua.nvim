-- persistent mode のテスト

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

t.test("persistent mode auto-enables skkelua on InsertEnter", function()
	local skkelua = require("skkelua")
	-- toggle の通知でテスト出力を汚さない
	local orig_notify = vim.notify
	vim.notify = function() end
	local ok, err = pcall(function()
		t.assert_equals(false, skkelua.is_persistent_mode())

		skkelua.toggle_persistent_mode()
		t.assert_equals(true, skkelua.is_persistent_mode())

		-- InsertEnter で skkelua が自動的に有効化される
		t.assert_equals(false, skkelua.is_enabled())
		vim.api.nvim_exec_autocmds("InsertEnter", { modeline = false })
		t.assert_equals(true, skkelua.is_enabled())

		-- 無効化すると自動有効化は止まる (skkelua 自体の状態は変えない)
		skkelua.toggle_persistent_mode()
		t.assert_equals(false, skkelua.is_persistent_mode())
		t.assert_equals(true, skkelua.is_enabled())

		skkelua._handle_request("disable", {}, vim_status)
		vim.api.nvim_exec_autocmds("InsertEnter", { modeline = false })
		t.assert_equals(false, skkelua.is_enabled())
	end)
	require("skkelua.persistent").disable()
	vim.notify = orig_notify
	if not ok then
		error(err, 0)
	end
end)

t.test("persistent mode is idempotent and fires user autocmds", function()
	local persistent = require("skkelua.persistent")
	local fired = {}
	local group = vim.api.nvim_create_augroup("test-persistent-autocmd", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "skkelua-persistent-enable", "skkelua-persistent-disable" },
		callback = function(ev)
			fired[#fired + 1] = ev.match
		end,
	})

	persistent.enable()
	persistent.enable() -- 2 回目は no-op
	persistent.disable()
	persistent.disable() -- 2 回目は no-op
	t.assert_equals({ "skkelua-persistent-enable", "skkelua-persistent-disable" }, fired)

	vim.api.nvim_del_augroup_by_id(group)
end)
