-- 組み込み以外の補完 UI (pum.vim / nvim-cmp / 外部 UI) の選択取得と確定。
-- 補完候補そのものは lsp.lua の in-process サーバーが返し、
-- ここは「いま何が選択されているか」と
-- 「選択中の候補を確定するキー」だけを UI ごとの差異として吸収する。

local M = {}

---@class skkelua.CompletionAdapter
---@field selected fun(): table? メニューで選択中の LSP CompletionItem (data を含む)。メニューが無い・未選択なら nil。item を持てない UI は空のテーブルで「選択中」だけを伝える
---@field confirm fun(): string 選択中の候補を確定するキー列 (termcode 済み。"<Cmd>" で始まる文字列なら <CR> を補って実行する)。同期的にテキストを変更しない

---@type skkelua.CompletionAdapter?
local adapter

local function is_truthy(v)
	return v == true or v == 1
end

--- pum.vim / cmp が持つ候補から LSP の CompletionItem を取り出す
---@param value any
---@return table
local function decode_item(value)
	if type(value) == "string" then
		local ok, decoded = pcall(vim.json.decode, value)
		value = ok and decoded or nil
	end
	return type(value) == "table" and value or {}
end

local pum_adapter = {
	selected = function()
		local info = vim.fn["pum#complete_info"]({ "selected" })
		if (info.selected or -1) < 0 then
			return nil
		end
		return decode_item(vim.tbl_get(vim.fn["pum#current_item"]() or {}, "user_data", "lspitem"))
	end,
	confirm = function()
		return "<Cmd>call pum#map#confirm()"
	end,
}

local cmp_adapter = {
	selected = function()
		local entry = package.loaded["cmp"].get_active_entry()
		return entry and entry:get_completion_item() or nil
	end,
	confirm = function()
		return "<Cmd>lua require('cmp').confirm({select = true})"
	end,
}

--- 補完 UI のアダプターを明示的に設定する。nil で自動検出に戻す。
--- アダプターは UI 自身の寿命・候補の変換・確定イベントを担当する
---@param value? skkelua.CompletionAdapter
function M.set_adapter(value)
	adapter = value
end

--- 表示中のメニューを持つ UI を検出する。組み込みの補完メニューなら nil。
--- 明示的に設定されたアダプターは自動検出より優先する
local function detect()
	if adapter then
		return adapter
	end
	if vim.fn.exists("*pum#visible") == 1 and is_truthy(vim.fn["pum#visible"]()) then
		return pum_adapter
	end
	local cmp = package.loaded["cmp"]
	if cmp then
		local ok, visible = pcall(cmp.visible)
		if ok and visible then
			return cmp_adapter
		end
	end
	return nil
end

--- アダプターの呼び出しで例外が出てもキー処理を止めない。
--- state() は打鍵ごとに呼ばれるため、壊れたアダプターが全ての入力を巻き込む
---@param what string
---@param fn function
---@return boolean ok
---@return any result
local function call_adapter(what, fn)
	local ok, result = pcall(fn)
	if not ok then
		vim.notify_once(("skkelua: completion adapter %s() failed: %s"):format(what, result), vim.log.levels.WARN)
	end
	return ok, result
end

--- 選択中の候補。組み込みの補完メニューが担当するときは external が false
---@return boolean external 組み込み以外の UI が担当するか
---@return table? item 選択中の CompletionItem
function M.selection()
	local active = detect()
	if not active then
		return false
	end
	local ok, item = call_adapter("selected", active.selected)
	-- 状態が分からない間は、未選択として扱う
	return true, ok and type(item) == "table" and item or nil
end

--- 選択中の候補を確定するキー列
---@return string?
function M.confirm()
	local active = detect()
	if not active then
		return nil
	end
	local ok, keys = call_adapter("confirm", active.confirm)
	return ok and type(keys) == "string" and keys or nil
end

--- skkelua の候補が選択時にバッファへ挿入する文字列
---@param item? table
---@return string?
function M.inserted_text(item)
	local data = M.item_data(item)
	return data and data.text or nil
end

--- CompletionItem が skkelua の候補なら、その data を返す
---@param item? table
---@return table?
function M.item_data(item)
	local data = item and item.data
	if type(data) == "table" and data.skkelua == true then
		return data
	end
	return nil
end

--- CompletionItem が skkelua の [辞書登録] 項目かどうか
---@param item? table
---@return boolean
function M.is_register_item(item)
	local data = M.item_data(item)
	return data ~= nil and data.register == true
end

return M
