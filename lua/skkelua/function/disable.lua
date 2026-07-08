-- 無効化・エスケープ (function/disable.ts に相当)

local M = {}

--- skkelua を無効化する
---@param context skkelua.Context
function M.disable(context)
	require("skkelua.function.common").kakutei(context)
	require("skkelua").disable_impl()
	require("skkelua.state").initialize_state(context.state)
end

--- <Esc> の処理
---@param context skkelua.Context
function M.escape(context)
	local config = require("skkelua.config").config
	if config.keepState then
		vim.api.nvim_create_augroup("skkelua", { clear = false })
		vim.api.nvim_create_autocmd("InsertEnter", {
			group = "skkelua",
			buffer = 0,
			once = true,
			callback = function()
				require("skkelua").handle("enable", {})
			end,
		})
	end
	M.disable(context)
	context.state.type = "escape"
end

return M
