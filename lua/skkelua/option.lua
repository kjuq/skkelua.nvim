-- オプションの保存・設定・復元 (autoload/skkeleton/internal/option.vim に相当)

local M = {}

---@type table<integer, integer> bufnr -> textwidth
local textwidth_vault = {}
---@type table<integer, string> winid -> virtualedit
local virtualedit_vault = {}

-- bufnr は再利用されるため、消えたバッファの保存内容は破棄する
vim.api.nvim_create_autocmd("BufWipeout", {
	group = vim.api.nvim_create_augroup("skkelua-option-vault", { clear = true }),
	callback = function(ev)
		textwidth_vault[ev.buf] = nil
	end,
})

function M.save_and_set()
	-- cmdline 関係ないオプションだけなので cmdline では飛ばす
	if vim.fn.mode() == "c" then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	if textwidth_vault[bufnr] == nil then
		textwidth_vault[bufnr] = vim.bo[bufnr].textwidth
	end
	if virtualedit_vault[winid] == nil then
		virtualedit_vault[winid] = vim.wo[winid].virtualedit
	end
	-- 不意に改行が発生してバッファが壊れるため 'textwidth' を無効化
	vim.bo[bufnr].textwidth = 0
	-- 末尾で送りあり変換をした際にバッファが壊れるため、一時的に 'virtualedit' を使う
	vim.wo[winid].virtualedit = "onemore"
end

function M.restore()
	if vim.fn.mode() == "c" then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	if textwidth_vault[bufnr] ~= nil then
		vim.bo[bufnr].textwidth = textwidth_vault[bufnr]
		textwidth_vault[bufnr] = nil
	end
	if virtualedit_vault[winid] ~= nil then
		vim.wo[winid].virtualedit = virtualedit_vault[winid]
		virtualedit_vault[winid] = nil
	end
end

return M
