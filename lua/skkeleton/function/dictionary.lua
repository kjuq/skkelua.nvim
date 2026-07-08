-- 辞書登録プロンプト (function/dictionary.ts に相当)

local M = {}

local cmap_keys = { "<Esc>", "<C-g>" }

--- 辞書登録プロンプトを開く
---@param context skkeleton.Context
---@return boolean 登録して確定した場合 true
function M.register_word(context)
	local config = require("skkeleton.config").config
	local store = require("skkeleton.store")
	local mode_mod = require("skkeleton.mode")
	local state = context.state --[[@as skkeleton.HenkanState]]

	require("skkeleton.map").save("c")
	for _, k in ipairs(cmap_keys) do
		vim.keymap.set("c", k, "__skkeleton_return__<CR>", { buffer = true, silent = true })
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
				require("skkeleton").map()
			end,
		})
		local input = vim.fn.input(base .. okuri .. ": ")
		if input == "" or input:find("__skkeleton_return__", 1, true) then
			vim.cmd("echo '' | redraw")
			return
		end
		state.candidates = { input }
		state.candidateIndex = 0
		require("skkeleton.function.common").kakutei(context)
		registered = true
	end)
	if not ok and config.debug then
		vim.print("registerWord interrupted")
		vim.print(err)
	end

	-- 後始末 (TS 版の finally 節に相当)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkeleton-enable-pre",
		modeline = false,
	})
	-- restore skkeleton mode
	require("skkeleton").map()
	vim.g["skkeleton#enabled"] = true
	vim.cmd.redrawstatus()
	vim.api.nvim_set_option_value("virtualedit", save_virtualedit, { win = 0 })
	-- restore stashed context
	store.set_context(context)
	-- and mode
	mode_mod.mode_change(context, context.mode)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkeleton-enable-post",
		modeline = false,
	})

	return registered
end

return M
