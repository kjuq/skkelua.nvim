-- 変換候補を Neovim builtin 補完へ流す in-process LSP サーバー
--
-- 変換入力中 (▽かんじ) に、見出しを前方一致検索した変換候補を
-- textDocument/completion の結果として返す。候補を確定すると
-- CompleteDone でユーザー辞書へ登録される。

local M = {}

local CLIENT_NAME = "skkelua"

local function completion_config()
	return require("skkelua.config").config.completion
end

--- buffer-local 'completeopt' を調整する。
--- 候補が 1 つだけでも pum を出すよう常に menuone を足す
--- (noselect は menu/menuone との併用でしか効かない)。
--- insertOnSelect では選択と同時に挿入するために noinsert を外し、
--- タイプ中に第一候補が勝手に入らないよう通常は noselect を足す。
--- auto_select (送り仮名確定直後) の応答では noselect も外し、
--- 第一候補が自動選択 + 挿入されるようにする
---@param buf integer
---@param auto_select? boolean
local function set_completeopt(buf, auto_select)
	local instant_insert = completion_config().insertOnSelect
	local values = { "menuone" }
	if instant_insert and not auto_select then
		values[#values + 1] = "noselect"
	end
	for _, o in ipairs(vim.opt_global.completeopt:get()) do
		local drop = o == "menuone" or (instant_insert and (o == "noinsert" or o == "noselect"))
		if not drop then
			values[#values + 1] = o
		end
	end
	vim.api.nvim_set_option_value("completeopt", table.concat(values, ","), { buf = buf })
end

--- vim.snippet の特殊文字 ($ と \) をエスケープする
---@param s string
---@return string
local function escape_snippet(s)
	return (s:gsub("[\\%$]", "\\%0"))
end

--- ひらがな (+ 長音・マーカー・送りローマ字) を triggerCharacters として列挙する
---@return string[]
local function trigger_characters()
	local chars = {}
	-- ぁ (U+3041) 〜 ゖ (U+3096)
	for cp = 0x3041, 0x3096 do
		chars[#chars + 1] = vim.fn.nr2char(cp)
	end
	chars[#chars + 1] = "ー"
	chars[#chars + 1] = require("skkelua.config").config.markerHenkan
	-- 候補選択 (▼送る) への遷移は markerHenkanSelect の挿入で検知する
	chars[#chars + 1] = require("skkelua.config").config.markerHenkanSelect
	-- 送りあり入力 (▽おく*r) で挿入されるのは "*" と送りのローマ字。
	-- 以降の絞り込みは isIncomplete による再リクエストが担うが、
	-- 初回トリガーのためにこれらも含める
	chars[#chars + 1] = "*"
	for i = 0, 25 do
		chars[#chars + 1] = string.char(97 + i) -- a-z
	end
	return chars
end

--- pum で選択中の自前候補の word がカーソル前に挿入されていればそれを返す。
--- insertOnSelect の選択挿入はバッファ上の pre-edit を候補 word で
--- 置き換えるため、その間に届いた再リクエストは pre-edit を見つけられない
---@param before_cursor string
---@return string? word
---@return table? data 候補の data (skkelua/midasi/word/type)
local function selected_word(before_cursor)
	local state = require("skkelua.completion").state()
	if state then
		local selected = state.visible and state.selected
		local data = selected and selected.item and selected.item.data
		if
			selected
			and selected.word ~= ""
			and data
			and data.skkelua
			and vim.endswith(before_cursor, selected.word)
		then
			return selected.word, data
		end
		return nil
	end
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

--- complete_info() の item が skkelua の [辞書登録] 項目かどうか
---@param pum_item? table
---@return boolean
function M.is_register_item(pum_item)
	local data = vim.tbl_get(pum_item or {}, "user_data", "nvim", "lsp", "completion_item", "data")
	return type(data) == "table" and data.skkelua == true and data.register == true
end

--- pum で選択中の自前候補の word が現在のカーソル前に挿入されていれば返す
--- (deletePreEdit の削除対象判定や、選択挿入中の接尾辞開始に使う)
---@return string? word
---@return table? data
function M.selected_word()
	if vim.fn.mode():sub(1, 1) == "c" then
		return selected_word(vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1))
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = (vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false) or {})[1] or ""
	return selected_word(line:sub(1, pos[2]))
end

--- 補完候補を組み立てる。
--- nil を返した場合は応答自体を保留する (complete() を走らせない)
---@return table? CompletionList
local function make_completion_list()
	local skkelua = require("skkelua")
	local pos = vim.api.nvim_win_get_cursor(0)
	local row, col = pos[1] - 1, pos[2]
	local line = vim.api.nvim_get_current_line()
	local pre_edit = skkelua.get_pre_edit()
	if
		skkelua.is_enabled()
		and pre_edit ~= ""
		and not vim.endswith(line:sub(1, col), pre_edit)
		and selected_word(line:sub(1, col))
	then
		return nil
	end
	local list = require("skkelua.completion").get({ line = line, row = row, col = col })
	if #list.items == 0 then
		return list
	end
	local instant_insert = completion_config().insertOnSelect
	local state = require("skkelua.store").get_context().state
	local auto_select = instant_insert
		and skkelua.phase() == "input:okuriari"
		and completion_config().deferOkuri
		and state.feed == ""
		and state.okuriFeed ~= ""
	set_completeopt(0, auto_select)
	for _, item in ipairs(list.items) do
		if instant_insert then
			item.filterText = nil
			if pre_edit:find("%w") then
				item.data.display = item.label
				item.label = pre_edit .. item.label
			end
		else
			-- Native completion needs snippet expansion to apply textEdit when
			-- its insertion word falls back to filterText.
			item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
			item.textEdit.newText = escape_snippet(item.textEdit.newText)
			item.insertText = item.textEdit.newText
		end
	end
	return list
end

--------------------------------------------------------------------
-- in-process server
--------------------------------------------------------------------

local function create_server(complete)
	return function(dispatchers)
		local closing, request_id = false, 0
		local pending = {}
		local srv = {}
		local function finish(id, err, result)
			local request = pending[id]
			if not request then
				return
			end
			pending[id] = nil
			if request.replied then
				request.replied(id)
			end
			-- Match vim.lsp.rpc: cancellation acknowledges tracking without invoking
			-- the consumer callback, which may already belong to an obsolete UI.
			if not (err and err.code == vim.lsp.protocol.ErrorCodes.RequestCancelled) then
				request.handler(err, result, id)
			end
		end
		function srv.request(method, params, handler, replied)
			if closing then
				return false
			end
			request_id = request_id + 1
			local id = request_id
			pending[id] = { handler = handler, replied = replied }
			vim.schedule(function()
				if not pending[id] then
					return
				end
				if method == "initialize" then
					finish(id, nil, {
						capabilities = {
							positionEncoding = "utf-8",
							completionProvider = { triggerCharacters = trigger_characters() },
						},
					})
				elseif method == "textDocument/completion" then
					local ok, list = pcall(complete, params)
					if not ok then
						finish(id, { code = -32603, message = tostring(list) })
					elseif list then
						table.insert(M._requests, { params = params, items = #list.items })
						finish(id, nil, list)
					end
				-- Native selection insertion can hold a response until cancellation.
				elseif method == "shutdown" then
					finish(id, nil, nil)
				else
					finish(id, { code = -32601, message = "Method not found: " .. method })
				end
			end)
			return true, id
		end
		function srv.notify(method, params)
			if closing then
				return false
			end
			if method == "$/cancelRequest" then
				vim.schedule(function()
					finish(
						params.id,
						{ code = vim.lsp.protocol.ErrorCodes.RequestCancelled, message = "Request cancelled" }
					)
				end)
			elseif method == "exit" then
				srv.terminate()
			end
			return true
		end
		function srv.is_closing()
			return closing
		end
		function srv.terminate()
			if closing then
				return
			end
			closing = true
			pending = {}
			vim.schedule(function()
				dispatchers.on_exit(0, 15)
			end)
		end
		return srv
	end
end

--- Read a request position from a loaded buffer without opening documents.
--- When bufnr is supplied, the caller is responsible for validating the URI.
---@param params table LSP completion params; character is a UTF-8 byte offset.
---@param bufnr? integer Explicit backing buffer for a virtual document or URI alias.
---@return {line: string, row: integer, col: integer}? context
---@return integer? bufnr
function M.get_context(params, bufnr)
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if bufnr == nil then
		for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
			if
				vim.api.nvim_buf_is_loaded(candidate)
				and vim.api.nvim_buf_get_name(candidate) ~= ""
				and vim.uri_from_bufnr(candidate) == params.textDocument.uri
			then
				bufnr = candidate
				break
			end
		end
		if bufnr == nil and vim.uri_from_bufnr(0) == params.textDocument.uri then
			bufnr = vim.api.nvim_get_current_buf()
		end
	end
	if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil
	end
	local row = params.position.line
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if line then
		return { line = line, row = row, col = params.position.character }, bufnr
	end
end

--- Create a transport for vim.lsp.start(). Never enables a completion UI.
--- The caller validates the input document; nil means no applicable context.
---@param get_context? fun(params: table): {line: string, row: integer, col: integer}?
---@return fun(dispatchers: table): table
function M.new_server(get_context)
	return create_server(function(params)
		local context = (get_context or M.get_context)(params)
		return context and require("skkelua.completion").get(context) or { isIncomplete = true, items = {} }
	end)
end

--- Attach a buffer to the shared external completion client, once per buffer.
--- Keeps the client alive across SKK enable/disable and never enables a UI.
---@param bufnr? integer Defaults to the current buffer.
---@return integer? client_id
function M.start(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, _uninitialized = true })) do
		if client.config.skkelua_external_completion and not client:is_stopped() then
			return client.id
		end
	end
	return vim.lsp.start({
		name = "skkelua",
		cmd = M.new_server(),
		skkelua_external_completion = true,
	}, {
		bufnr = bufnr,
		reuse_client = function(client)
			return client.config.skkelua_external_completion == true and not client:is_stopped()
		end,
	})
end

local function new_server()
	return create_server(make_completion_list)
end

--------------------------------------------------------------------
-- attach / detach
--------------------------------------------------------------------

--- 候補確定時にユーザー辞書へ登録する
--- (テスト用に reason と completed_item を注入できるよう分離している)
---@param reason? string v:event.reason ("accept"/"cancel"/"discard")
---@param completed_item? table v:completed_item
function M._on_complete_done(reason, completed_item)
	-- <Esc>/<C-e> などで確定せず閉じた場合 (cancel/discard) は登録しない。
	-- reason が取れない環境では従来通り登録する
	if reason ~= nil and reason ~= "accept" then
		return
	end
	local item = vim.tbl_get(completed_item or {}, "user_data", "nvim", "lsp", "completion_item")
	require("skkelua.completion").accept(item)
end

local function on_complete_done()
	M._on_complete_done(vim.tbl_get(vim.v.event, "reason"), vim.v.completed_item)
end

--- buffer-local 'completeopt' をグローバル値に戻す
---@param buf integer
local function restore_completeopt(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("setlocal completeopt<")
		end)
	end
end

--- ASCII 混じり pre-edit ではフィルタを通すため label に pre-edit を
--- 前置している。pum の表示 (abbr) は候補そのものへ戻す。
--- また detail (見出し) はクライアントが info に写し、'completeopt' の
--- popup で候補選択のたびにフロートとして出てしまうため、常に空へ戻す
---@param item table lsp.CompletionItem
---@return table
local function convert_item(item)
	local display = vim.tbl_get(item, "data", "display")
	return { info = "", abbr = display }
end

---@param client_id integer
---@param buf integer
local function enable_completion(client_id, buf)
	-- Note: builtin の completion.enable は「最初に buf_handle を作った呼び出しの
	--       opts」でバッファの補完動作が固定される。有効化・無効化サイクルを
	--       冪等にするため、一度無効化してから autotrigger 付きで登録し直す
	--       (それでも他の設定が同一バッファへ opts 無しで enable(true) を呼ぶと
	--       autotrigger は失われる。doc の注意書きを参照)
	vim.lsp.completion.enable(false, client_id, buf)
	vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true, convert = convert_item })
	set_completeopt(buf, false)
	vim.api.nvim_create_autocmd("CompleteDone", {
		group = vim.api.nvim_create_augroup("skkelua-lsp-complete-done", { clear = true }),
		callback = on_complete_done,
	})
end

--- 現在のバッファで補完を有効にする (skkelua-enable-post から呼ばれる)
function M.attach()
	if not completion_config().enabled then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local client_id = vim.lsp.start({
		name = CLIENT_NAME,
		cmd = new_server(),
		skkelua_builtin_completion = true,
	}, {
		bufnr = buf,
		reuse_client = function(client)
			return client.name == CLIENT_NAME
				and client.config.skkelua_builtin_completion == true
				and not client:is_stopped()
		end,
	})
	if not client_id then
		return
	end
	-- Note: triggerCharacters は completion.enable 時に server_capabilities から
	--       読まれるため、initialize 完了前に呼ぶと autotrigger が働かない。
	--       未初期化の場合は LspAttach (setup_autocmds で登録) に任せる
	local client = vim.lsp.get_client_by_id(client_id)
	if client and client.initialized then
		enable_completion(client_id, buf)
	end
end

local function builtin_client(buf)
	for _, client in ipairs(vim.lsp.get_clients({ name = CLIENT_NAME, bufnr = buf })) do
		if client.config.skkelua_builtin_completion then
			return client
		end
	end
end

--- 現在のバッファで補完を明示的にトリガーする。
--- autotrigger はトリガー文字のタイプでしか働かないため、辞書登録の
--- キャンセルなどタイプを伴わずに pre-edit が復元された時に呼ぶ
function M.trigger()
	if require("skkelua.completion").trigger() then
		return
	end
	if not completion_config().enabled or vim.fn.mode() ~= "i" then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local client = builtin_client(buf)
	if not client then
		return
	end
	vim.lsp.completion.get()
end

--- 現在のバッファで補完を無効にする (skkelua-disable-post から呼ばれる)
function M.detach()
	local buf = vim.api.nvim_get_current_buf()
	local client = builtin_client(buf)
	if client then
		vim.lsp.completion.enable(false, client.id, buf)
		restore_completeopt(buf)
	end
end

--- 有効化・無効化に連動する autocmd を登録する (plugin/skkelua.lua から呼ばれる)
function M.setup_autocmds()
	local group = vim.api.nvim_create_augroup("skkelua-lsp", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "skkelua-enable-post",
		callback = function()
			M.attach()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "skkelua-disable-post",
		callback = function()
			M.detach()
		end,
	})
	-- initialize 完了後の attach を拾って autotrigger を有効化する
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if client and client.config.skkelua_builtin_completion then
				enable_completion(ev.data.client_id, ev.buf)
			end
		end,
	})
end

--- テスト用: completion list を直接組み立てる
function M._make_completion_list()
	return make_completion_list()
end

-- テスト用: 処理した completion リクエストの記録
M._requests = {}

return M
