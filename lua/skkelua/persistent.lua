-- persistent mode
-- insert モードに入るたびに skkelua を自動的に有効化する常駐モード。
-- 「しばらく日本語を書き続ける」ときに毎回有効化キーを押す手間を省く

local M = {}

local AUGROUP = "skkelua-persistent"

local enabled = false

---@return boolean
function M.is_enabled()
	return enabled
end

--- 有効化: 以後 InsertEnter のたびに skkelua を有効化する
function M.enable()
	if enabled then
		return
	end
	enabled = true
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = vim.api.nvim_create_augroup(AUGROUP, { clear = true }),
		callback = function()
			require("skkelua").handle("enable", {})
		end,
	})
	vim.api.nvim_exec_autocmds("User", { pattern = "skkelua-persistent-enable", modeline = false })
end

--- 無効化: 自動有効化をやめる (現在の skkelua の有効・無効は変えない)
function M.disable()
	if not enabled then
		return
	end
	enabled = false
	vim.api.nvim_create_augroup(AUGROUP, { clear = true })
	vim.api.nvim_exec_autocmds("User", { pattern = "skkelua-persistent-disable", modeline = false })
end

--- トグル (状態の通知付き)
function M.toggle()
	if enabled then
		M.disable()
		vim.notify("skkelua: persistent mode disabled")
	else
		M.enable()
		vim.notify("skkelua: persistent mode enabled")
	end
end

return M
