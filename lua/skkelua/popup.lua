-- 候補ポップアップ (autoload/skkeleton/popup.vim に相当)

local M = {}

---@type integer[]
local windows = {}

---@param candidates string[]
local function open_cmdline(candidates)
	local top = vim.o.lines + 1 - math.max(1, vim.o.cmdheight) - #candidates
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, candidates)
	local width = 1
	for _, c in ipairs(candidates) do
		width = math.max(width, vim.fn.strwidth(c))
	end
	local win = vim.api.nvim_open_win(buf, false, {
		border = "none",
		relative = "editor",
		width = width,
		height = #candidates,
		col = vim.fn.getcmdscreenpos(),
		row = top,
		style = "minimal",
	})
	vim.cmd.redraw()
	windows[#windows + 1] = win
end

---@param candidates string[]
local function open(candidates)
	vim.api.nvim_create_autocmd("User", {
		pattern = "skkeleton-handled",
		once = true,
		callback = function()
			M.close()
		end,
	})
	if vim.fn.mode() == "c" then
		open_cmdline(candidates)
		return
	end
	local spos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
	-- Note: Neovim では echo area に floatwin を被せるのが許可されておらず、
	--       ずれるため offset 付けることで弾く
	local offset = vim.o.cmdheight
	local linvert = vim.o.lines - spos.row - offset < #candidates
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, candidates)
	local width = 1
	for _, c in ipairs(candidates) do
		width = math.max(width, vim.fn.strwidth(c))
	end
	local win = vim.api.nvim_open_win(buf, false, {
		border = "none",
		relative = "cursor",
		width = width,
		height = #candidates,
		col = 0,
		row = linvert and 0 or 1,
		anchor = linvert and "SW" or "NW",
		style = "minimal",
	})
	windows[#windows + 1] = win
end

--- 候補ポップアップの表示を予約する
--- (実際の表示はキー処理が終わった skkeleton-handled のタイミングで行う)
---@param candidates string[]
function M.open(candidates)
	vim.api.nvim_create_autocmd("User", {
		pattern = "skkeleton-handled",
		once = true,
		callback = function()
			open(candidates)
		end,
	})
end

function M.close()
	for _, win in ipairs(windows) do
		pcall(vim.api.nvim_win_close, win, true)
	end
	windows = {}
end

return M
