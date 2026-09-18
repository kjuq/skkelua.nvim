-- Optional compatibility with completion menus already configured by the user.
-- Candidate sources and acceptance events remain owned by those plugins.
local M = {}

local function keys(command)
	return vim.api.nvim_replace_termcodes("<Cmd>" .. command .. "<CR>", true, false, true)
end

local function lsp_item(item)
	local value = vim.tbl_get(item or {}, "user_data", "lspitem")
	if type(value) == "string" then
		local ok, decoded = pcall(vim.json.decode, value)
		value = ok and decoded or nil
	end
	return type(value) == "table" and value or {}
end

local pum_adapter = {
	state = function()
		local info = vim.fn["pum#complete_info"]({ "pum_visible", "selected", "inserted" })
		local selected = (info.selected or -1) >= 0 and vim.fn["pum#current_item"]()
		return {
			visible = info.pum_visible == true or info.pum_visible == 1,
			selected = (info.selected or -1) >= 0 and { word = info.inserted or "", item = lsp_item(selected) } or nil,
		}
	end,
	confirm = function()
		return keys("call pum#map#confirm()")
	end,
}

local cmp_adapter = {
	state = function()
		local cmp = package.loaded.cmp
		local entry = cmp.get_active_entry()
		return {
			visible = true,
			-- cmp does not expose whether a selected entry has already been inserted.
			selected = entry and { word = "", item = entry:get_completion_item() } or nil,
		}
	end,
	confirm = function()
		return keys("lua require('cmp').confirm({select = true})")
	end,
}

function M.detect()
	if vim.fn.exists("*pum#visible") == 1 then
		local visible = vim.fn["pum#visible"]()
		if visible == true or visible == 1 then
			return pum_adapter
		end
	end
	local cmp = package.loaded.cmp
	if cmp then
		local ok, visible = pcall(cmp.visible)
		if ok and visible then
			return cmp_adapter
		end
	end
	return nil
end

return M
