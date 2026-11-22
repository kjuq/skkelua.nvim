-- 補完 UI と skkelua のキー処理をつなぐ Neovim 側の処理
--
-- 候補の生成と、確定時の辞書学習・登録は LSP サーバー (lsp.lua, lsp/list.lua)
-- が担い、サーバーは状態を持たない。ここでは補完 UI で選ばれている
-- skkelua の候補を、バッファと skkelua の状態から求める。
--   builtin の pum: complete_info() の選択項目
--   他の補完 UI: pre-edit の位置へ挿入された候補の文字列 (UI には問い合わせない)

local M = {}

local function termcode(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

--- builtin の pum で選択中の自前候補の word がカーソル前に挿入されていればそれを返す。
--- insertOnSelect の選択挿入はバッファ上の pre-edit を候補 word で
--- 置き換えるため、その間に届いた再リクエストは pre-edit を見つけられない
---@param before_cursor string
---@return string? word
---@return table? data 候補の data (skkelua/midasi/word/type)
function M.native_selected_word(before_cursor)
	if vim.fn.pumvisible() == 0 then
		return nil
	end
	local info = vim.fn.complete_info({ "selected", "items" })
	local sel = (info.selected or -1) >= 0 and info.items[info.selected + 1] or nil
	local word = sel and sel.word
	if not word or word == "" or not vim.endswith(before_cursor, word) then
		return nil
	end
	local item = vim.tbl_get(sel, "user_data", "nvim", "lsp", "completion_item")
	if not (item and vim.tbl_get(item, "data", "skkelua")) then
		return nil
	end
	return word, item.data
end

--------------------------------------------------------------------
-- 補完 UI による候補の挿入の検出
--------------------------------------------------------------------

-- 補完 UI が skkelua のクライアントへ補完を要求した時点の pre-edit の位置。
-- Neovim の LSP クライアントが出す LspRequest で記録する (サーバーの応答は見ない)
---@type {bufnr: integer, row: integer, prefix: string, pre_edit: string}?
local requested

--- カーソル前に skkelua が描いた pre-edit がそのまま残っていれば、その位置を返す
---@param bufnr integer
---@return {bufnr: integer, row: integer, prefix: string, pre_edit: string}?
local function intact_pre_edit(bufnr)
	if bufnr ~= vim.api.nvim_get_current_buf() then
		return nil
	end
	local shown = require("skkelua.store").get_context().preEdit:shown()
	if shown == "" then
		return nil
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	local before = vim.api.nvim_get_current_line():sub(1, pos[2])
	if not vim.endswith(before, shown) then
		return nil
	end
	return { bufnr = bufnr, row = pos[1] - 1, prefix = before:sub(1, #before - #shown), pre_edit = shown }
end

---@param ev {data: {client_id: integer, request: {type: string, bufnr: integer, method: string}}}
local function on_request(ev)
	local request = ev.data.request
	if request.type ~= "pending" then
		return
	end
	local client = vim.lsp.get_client_by_id(ev.data.client_id)
	if not (client and client.name == require("skkelua.lsp").CLIENT_NAME) then
		return
	end
	if request.method == "workspace/executeCommand" then
		-- 補完 UI が確定した候補 (item.command の実行) は、以降のキーで確定し直さない
		requested = nil
	elseif request.method == "textDocument/completion" then
		-- 候補の挿入後の再要求 (pre-edit が残っていない) では、挿入前の記録を残す
		requested = intact_pre_edit(request.bufnr) or requested
	end
end

--- 補完 UI による候補の挿入を検出するための autocmd を登録する
--- (plugin/skkelua.lua から呼ばれる)
function M.setup_autocmds()
	local group = vim.api.nvim_create_augroup("skkelua-completion-ui", { clear = true })
	vim.api.nvim_create_autocmd("LspRequest", {
		group = group,
		callback = function(ev)
			on_request(ev)
		end,
	})
end

--- 補完 UI が pre-edit を置き換えて挿入している skkelua の候補を返す。
--- skkelua が描いたつもりの pre-edit (shown) が補完の要求時と同じで、
--- その位置に今の状態の候補の文字列が入っていれば、UI が候補を挿入したと判断する
---@param before_cursor string カーソル前のテキスト
---@param shown string skkelua が描いた pre-edit
---@return string? word
---@return table? data 候補の data
local function inserted_candidate(before_cursor, shown)
	local req = requested
	if not req or shown == "" or shown ~= req.pre_edit then
		return nil
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	if vim.api.nvim_get_current_buf() ~= req.bufnr or pos[1] - 1 ~= req.row then
		return nil
	end
	if before_cursor:sub(1, #req.prefix) ~= req.prefix then
		return nil
	end
	local word = before_cursor:sub(#req.prefix + 1)
	if word == "" or word == req.pre_edit then
		return nil
	end
	-- 候補はサーバーと同じ組み立て (lsp/list.lua) で、要求時の行から引き直す
	local list = require("skkelua.lsp.list").build({
		line = req.prefix .. req.pre_edit,
		row = req.row,
		col = #req.prefix + #req.pre_edit,
	})
	for _, item in ipairs(list.items) do
		local data = item.data
		-- [辞書登録] の挿入テキストは pre-edit そのものなので、ここには来ない
		if data and data.skkelua and not data.register and data.text == word then
			return word, data
		end
	end
end

--- 補完メニューの状態を返す (init.lua の vim_status から呼ばれる)。
--- builtin の pum が無いときは、補完 UI が挿入した skkelua の候補を探し、
--- 見つかれば "inserted" として、その候補を選択中の native と同じ形で返す
---@param mode string
---@param prev_input string カーソル前のテキスト
---@return string complete_type "native" | "inserted"
---@return table info
function M.complete_info(mode, prev_input)
	if mode == "i" and vim.fn.pumvisible() == 0 then
		local shown = require("skkelua.store").get_context().preEdit:shown()
		local word, data = inserted_candidate(prev_input, shown)
		if word then
			local item = { word = word, user_data = { nvim = { lsp = { completion_item = { data = data } } } } }
			return "inserted", { pum_visible = 1, selected = 0, items = { item } }
		end
	end
	-- items は選択中の [辞書登録] 項目の判定 (init.lua の handle_impl) に使う
	return "native", vim.fn.complete_info({ "pum_visible", "selected", "items" })
end

--------------------------------------------------------------------
-- キー処理中の選択
--------------------------------------------------------------------

-- キー処理中に、補完 UI が挿入していると判定された候補
---@type {word: string, data: table}?
local key_selection

--- キー処理の開始時に、補完 UI が挿入している候補を受け取る
--- (init.lua の handle_request から呼ばれる)
---@param vim_status skkelua.VimStatus
function M.begin_key(vim_status)
	key_selection = nil
	if vim_status.completeType == "inserted" then
		local item = vim_status.completeInfo.items[1]
		key_selection = {
			word = item.word,
			data = vim.tbl_get(item, "user_data", "nvim", "lsp", "completion_item", "data"),
		}
	end
end

--- 補完メニューで選択中の自前候補の word が現在のカーソル前に挿入されていれば返す
--- (deletePreEdit の削除対象判定や、選択挿入中の接尾辞開始に使う)
---@return string? word
---@return table? data
function M.selected_word()
	if vim.fn.pumvisible() == 1 then
		local pos = vim.api.nvim_win_get_cursor(0)
		local line = (vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false) or {})[1] or ""
		return M.native_selected_word(line:sub(1, pos[2]))
	end
	if key_selection then
		return key_selection.word, key_selection.data
	end
end

--- 補完で挿入された候補を、挿入前の pre-edit 表示に戻す。
--- builtin の pum は <C-e> で閉じ、他の補完 UI が挿入した候補はバッファを
--- 直接書き戻す (init.lua の _revert_completion から呼ばれる。
--- マクロの再生など、候補が挿入されていなければ何もしない)
function M.revert()
	if vim.fn.pumvisible() == 1 then
		vim.api.nvim_feedkeys(termcode("<C-e>"), "ni", false)
		return
	end
	local req = requested
	if not (req and key_selection) or vim.api.nvim_get_current_buf() ~= req.bufnr then
		return
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	if pos[1] - 1 ~= req.row then
		return
	end
	local line = vim.api.nvim_get_current_line()
	if line:sub(1, #req.prefix) ~= req.prefix or line:sub(#req.prefix + 1, pos[2]) ~= key_selection.word then
		return
	end
	vim.api.nvim_buf_set_text(0, req.row, #req.prefix, req.row, pos[2], { req.pre_edit })
	vim.api.nvim_win_set_cursor(0, { pos[1], #req.prefix + #req.pre_edit })
	requested = nil
end

--- テスト用: 記録した要求とキー処理中の選択を忘れる
function M._reset_for_test()
	requested = nil
	key_selection = nil
end

return M
