-- 辞書登録プロンプト (function/dictionary.ts に相当)

local M = {}

local cmap_keys = { "<Esc>", "<C-g>" }

--- 辞書登録プロンプトを開く
---@param context skkelua.Context
---@return boolean 登録して確定した場合 true
function M.register_word(context)
	local config = require("skkelua.config").config
	local store = require("skkelua.store")
	local mode_mod = require("skkelua.mode")
	local state = context.state --[[@as skkelua.HenkanState]]

	require("skkelua.map").save("c")
	for _, k in ipairs(cmap_keys) do
		vim.keymap.set("c", k, "__skkelua_return__<CR>", { buffer = true, silent = true })
	end

	-- Note: use virtualedit for fix slip cursor position at line ending.
	local save_virtualedit = vim.api.nvim_get_option_value("virtualedit", { win = 0 })
	vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })

	local registered = false
	local ok, err = pcall(function()
		local base = "[辞書登録] " .. state.henkanFeed
		local okuri = state.mode == "okuriari" and ("*" .. state.okuriFeed) or ""
		store.init_context()
		vim.api.nvim_create_autocmd("CmdlineEnter", {
			once = true,
			callback = function()
				require("skkelua").map()
			end,
		})
		local input = vim.fn.input(base .. okuri .. ": ")
		if input == "" or input:find("__skkelua_return__", 1, true) then
			vim.cmd("echo '' | redraw")
			return
		end
		state.candidates = { input }
		state.candidateIndex = 0
		require("skkelua.function.common").kakutei(context)
		registered = true
	end)
	if not ok and config.debug then
		vim.print("registerWord interrupted")
		vim.print(err)
	end

	-- 後始末 (TS 版の finally 節に相当)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkelua-enable-pre",
		modeline = false,
	})
	-- restore skkelua mode
	require("skkelua").map()
	require("skkelua.store").status.enabled = true
	vim.cmd.redrawstatus()
	vim.api.nvim_set_option_value("virtualedit", save_virtualedit, { win = 0 })
	-- restore stashed context
	store.set_context(context)
	-- and mode
	mode_mod.mode_change(context, context.mode)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkelua-enable-post",
		modeline = false,
	})

	return registered
end

return M
