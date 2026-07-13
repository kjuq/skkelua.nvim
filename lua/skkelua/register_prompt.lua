-- 辞書登録用のフローティングプロンプト
--
-- buftype=prompt のバッファを insert モードで開くため、cmdline の
-- vim.fn.input() と違い skkelua のかな入力も LSP 補完 (pum) も
-- 本文と同じように使える

local M = {}

---@class skkelua.RegisterPromptOpts
---@field title string
---@field on_confirm fun(input: string)
---@field on_cancel fun()

---@type { win: integer, buf: integer }?
local current = nil

--- プロンプトを閉じる (コールバックは呼ばない)
local function close()
	if not current then
		return
	end
	local win, buf = current.win, current.buf
	current = nil
	vim.cmd("stopinsert")
	pcall(vim.api.nvim_win_close, win, true)
	pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

--- プロンプトを開く
---@param opts skkelua.RegisterPromptOpts
function M.open(opts)
	if current then
		close()
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "prompt"
	vim.fn.prompt_setprompt(buf, "> ")

	local title = (" %s "):format(opts.title)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = math.max(vim.fn.strwidth(title) + 2, 30),
		height = 1,
		style = "minimal",
		border = "single",
		title = title,
		title_pos = "left",
	})
	current = { win = win, buf = buf }

	-- 確定・キャンセルは一度だけ、プロンプトを閉じてから呼ぶ
	local done = false
	---@param cb function
	local function finish(cb, ...)
		if done then
			return
		end
		done = true
		local args = { ... }
		close()
		vim.schedule(function()
			cb(unpack(args))
		end)
	end

	vim.fn.prompt_setcallback(buf, function(text)
		finish(opts.on_confirm, text)
	end)
	vim.fn.prompt_setinterrupt(buf, function()
		finish(opts.on_cancel)
	end)

	-- :fclose! などで外部からウィンドウを閉じられた場合もキャンセル扱いにする
	-- (自前の close() 経由でも発火するが、done フラグで no-op になる)
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			-- イベント処理中のバッファ削除を避けるため schedule する
			vim.schedule(function()
				finish(opts.on_cancel)
			end)
		end,
	})

	-- skkelua を有効化する (skkelua-enable-post で LSP 補完もこの
	-- バッファへ attach し、プロンプト内でも pum で変換できる)
	require("skkelua").handle("enable", {})

	-- <Esc> はプロンプトのキャンセル (skkelua の escape 機能より優先
	-- させるため、skkelua のマップの後に buffer-local で上書きする)
	vim.keymap.set({ "i", "n" }, "<Esc>", function()
		finish(opts.on_cancel)
	end, { buffer = buf, nowait = true })

	vim.cmd("startinsert!")
end

--- テスト用: 現在のプロンプトの win/buf を返す
---@return { win: integer, buf: integer }?
function M._current()
	return current
end

--- テスト用: コールバックを呼ばずに閉じる
M._close = close

return M
