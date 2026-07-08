-- 入力モードの切り替え (mode.ts に相当)

local state_mod = require("skkeleton.state")

local M = {}

--- モードを変更し g:skkeleton#mode へ反映する
---@param context skkeleton.Context
---@param mode string
function M.mode_change(context, mode)
	local config = require("skkeleton.config").config
	local store = require("skkeleton.store")
	context.mode = mode
	vim.g["skkeleton#mode"] = mode
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkeleton-mode-changed",
		modeline = false,
	})
	if config.keepMode then
		store.variables.lastMode = mode
	end
end

--- abbrev モードを考慮して state を初期化する
---@param context skkeleton.Context
---@param ignore? string[]
function M.initialize_state_with_abbrev(context, ignore)
	if context.mode == "abbrev" then
		M.mode_change(context, "hira")
		local filtered = {}
		for _, key in ipairs(ignore or {}) do
			if key ~= "converter" and key ~= "table" then
				filtered[#filtered + 1] = key
			end
		end
		ignore = filtered
	end
	state_mod.initialize_state(context.state, ignore)
end

return M
