-- 辞書登録用のフローティングプロンプト
--
-- buftype=prompt のバッファを insert モードで開くため、cmdline の
-- vim.fn.input() と違い skkelua のかな入力も LSP 補完 (pum) も
-- 本文と同じように使える
--
-- プロンプト内の変換から register_word が再帰的に呼ばれた場合は
-- スタックへ積んでネスト登録に対応する。内側のプロンプトは外側の
-- 右下へずらして表示し、閉じると外側プロンプトへ復帰する

local M = {}

---@class skkelua.RegisterPromptOpts
---@field title string
---@field on_confirm fun(input: string)
---@field on_cancel fun()

---@class skkelua.RegisterPromptEntry
---@field win integer
---@field buf integer
---@field done boolean
---@field on_confirm fun(input: string)
---@field on_cancel fun()

---@type skkelua.RegisterPromptEntry[]
local stack = {}

---@param entry skkelua.RegisterPromptEntry
---@return integer?
local function index_of(entry)
	for i, e in ipairs(stack) do
		if e == entry then
			return i
		end
	end
end

--- entry のプロンプトを閉じる (コールバックは呼ばない)
--- Note: WinClosed 経由で schedule 済みの finish を無効化するため、
---       ウィンドウを閉じる前に done を立てる
---@param entry skkelua.RegisterPromptEntry
local function close(entry)
	local i = index_of(entry)
	if not i then
		return
	end
	table.remove(stack, i)
	entry.done = true
	vim.cmd("stopinsert")
	pcall(vim.api.nvim_win_close, entry.win, true)
	pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
end

--- entry より内側 (上) に積まれたプロンプトをコールバック無しで破棄する。
--- 内側の確定・キャンセルは外側プロンプトのウィンドウへ復元・置換しようと
--- するため、外側ごと閉じる場合はコールバックを呼べない
---@param entry skkelua.RegisterPromptEntry
local function discard_above(entry)
	local i = index_of(entry)
	if not i then
		return
	end
	for j = #stack, i + 1, -1 do
		close(stack[j])
	end
end

--- 確定・キャンセルは一度だけ、プロンプトを閉じてから呼ぶ
---@param entry skkelua.RegisterPromptEntry
---@param cb function
local function finish(entry, cb, ...)
	if entry.done then
		return
	end
	local args = { ... }
	discard_above(entry)
	close(entry)
	vim.schedule(function()
		cb(unpack(args))
	end)
end

--- プロンプトを開く。最上位プロンプトの中から呼ばれた場合はネストとして積む
---@param opts skkelua.RegisterPromptOpts
function M.open(opts)
	-- プロンプト外から開き直された場合は既存のスタックを黙って破棄する
	local top = stack[#stack]
	if top and vim.api.nvim_get_current_win() ~= top.win then
		M._close()
		top = nil
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "prompt"
	vim.fn.prompt_setprompt(buf, "> ")

	local title = (" %s "):format(opts.title)
	---@type vim.api.keyset.win_config
	local win_config = {
		relative = "cursor",
		row = 1,
		col = 0,
		width = math.max(vim.fn.strwidth(title) + 2, 30),
		height = 1,
		style = "minimal",
		border = "single",
		title = title,
		title_pos = "left",
		zindex = 50 + #stack,
	}
	if top then
		-- ネスト時は外側プロンプトの右下へずらし、スタックを見えるようにする
		win_config.relative = "win"
		win_config.win = top.win
		win_config.row = 2
		win_config.col = 2
	end
	local win = vim.api.nvim_open_win(buf, true, win_config)

	---@type skkelua.RegisterPromptEntry
	local entry = {
		win = win,
		buf = buf,
		done = false,
		on_confirm = opts.on_confirm,
		on_cancel = opts.on_cancel,
	}
	stack[#stack + 1] = entry

	vim.fn.prompt_setcallback(buf, function(text)
		finish(entry, opts.on_confirm, text)
	end)
	vim.fn.prompt_setinterrupt(buf, function()
		finish(entry, opts.on_cancel)
	end)

	-- :fclose! などで外部からウィンドウを閉じられた場合もキャンセル扱いにする
	-- (自前の close() 経由でも発火するが、done フラグで no-op になる)
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			-- イベント処理中のバッファ削除を避けるため schedule する
			vim.schedule(function()
				finish(entry, opts.on_cancel)
			end)
		end,
	})

	-- skkelua を有効化する (skkelua-enable-post で LSP 補完もこの
	-- バッファへ attach し、プロンプト内でも pum で変換できる)
	require("skkelua").handle("enable", {})

	-- <Esc> はプロンプトのキャンセル (skkelua の escape 機能より優先
	-- させるため、skkelua のマップの後に buffer-local で上書きする)
	vim.keymap.set({ "i", "n" }, "<Esc>", function()
		finish(entry, opts.on_cancel)
	end, { buffer = buf, nowait = true })

	vim.cmd("startinsert!")
end

--- テスト用: 最上位プロンプトの win/buf を返す
---@return skkelua.RegisterPromptEntry?
function M._current()
	return stack[#stack]
end

--- テスト用: スタックのコピーを返す (外側から内側の順)
---@return skkelua.RegisterPromptEntry[]
function M._stack()
	return vim.list_slice(stack)
end

--- テスト用: 最上位プロンプトを確定する (headless では <CR> を撃てない)
---@param input string
function M._confirm(input)
	local top = stack[#stack]
	if top then
		finish(top, top.on_confirm, input)
	end
end

--- テスト用: コールバックを呼ばずに全て閉じる
function M._close()
	while #stack > 0 do
		close(stack[#stack])
	end
end

return M
