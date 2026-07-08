-- 無効化・エスケープ (function/disable.ts に相当)

local M = {}

--- skkeleton を無効化する
---@param context skkeleton.Context
function M.disable(context)
	require("skkeleton.function.common").kakutei(context)
	require("skkeleton").disable_impl()
	require("skkeleton.state").initialize_state(context.state)
end

--- <Esc> の処理
---@param context skkeleton.Context
function M.escape(context)
	local config = require("skkeleton.config").config
	if config.keepState then
		vim.api.nvim_create_augroup("skkeleton", { clear = false })
		vim.api.nvim_create_autocmd("InsertEnter", {
			group = "skkeleton",
			buffer = 0,
			once = true,
			callback = function()
				require("skkeleton").handle("enable", {})
			end,
		})
	end
	M.disable(context)
	context.state.type = "escape"
end

return M
