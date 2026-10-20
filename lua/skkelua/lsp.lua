-- 変換候補を LSP (builtin 補完・外部の補完 UI) へ流す in-process サーバー
--
-- 変換入力中 (▽かんじ) に、見出しを前方一致検索した変換候補を
-- textDocument/completion の結果として返す。候補を確定すると、
-- クライアントが実行する item.command (skkelua.accept) で
-- ユーザー辞書へ登録される。

local M = {}

local CLIENT_NAME = "skkelua"

local list_of = require("skkelua.lsp.list")

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
	local completion = require("skkelua.completion")
	local external, item = completion.selection()
	if external then
		-- 選択挿入は pre-edit を候補の文字列で置き換える。UI が実際に挿入した
		-- 文字列は分からないので、候補の挿入文字列がカーソル前にあるかで判断する
		local word = completion.inserted_text(item)
		if word and word ~= "" and vim.endswith(before_cursor, word) then
			return word, completion.item_data(item)
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

--- pum で選択中の自前候補の word が現在のカーソル前に挿入されていれば返す
--- (deletePreEdit の削除対象判定や、選択挿入中の接尾辞開始に使う)
---@return string? word
---@return table? data
function M.selected_word()
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = (vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false) or {})[1] or ""
	return selected_word(line:sub(1, pos[2]))
end

--- 補完候補を組み立てる。
--- nil を返した場合は応答自体を保留する (complete() を走らせない)
---@return table? CompletionList
local function make_completion_list()
	-- Note: params.position は使わない。pre-edit の再描画 (BS + 再挿入) は
	--       InsertCharPre ごとにリクエストを積むので、後発の処理時点では
	--       バッファが先へ進んでいることがある。クライアント (builtin) も
	--       応答を処理時点のカーソルで解釈するため、常に現在位置で組み立てる
	local pos = vim.api.nvim_win_get_cursor(0)
	local row, col = pos[1] - 1, pos[2] -- utf-8 (byte)
	local line = (vim.api.nvim_buf_get_lines(0, row, row + 1, false) or {})[1] or ""
	local list, reason = require("skkelua.lsp.list").build({ line = line, row = row, col = col })
	if reason == "stale" then
		-- insertOnSelect の選択挿入中 (バッファは pre-edit でなく候補 word) に
		-- 届いた後発リクエスト。pre-edit の再描画は InsertCharPre ごとに
		-- リクエストを積むため、選択挿入を起こした応答の後にも同じ状態への
		-- リクエストが残っている。ここで空を返すと complete() が pum を閉じ、
		-- 同じ候補を返し直しても complete() の再実行で typed text が候補 word に
		-- すり替わり <C-p>/<C-e> で pre-edit に戻れなくなる。
		-- 応答を保留して、表示中の pum と選択状態をそのまま保つ
		if selected_word(line:sub(1, col)) then
			return nil
		end
		return list
	elseif reason then
		return list
	end

	local instant_insert = completion_config().insertOnSelect
	local pre_edit = require("skkelua").get_pre_edit()
	-- typed text (pre-edit) に ASCII 英数字が含まれるとクライアント側の
	-- fuzzy フィルタが有効になり、素の label ではマッチしなくなる。
	-- その場合は label に pre-edit を前置してフィルタを通し、
	-- 表示は convert フック (enable 時に登録) で候補のみへ戻す
	local prefixed_label = pre_edit:find("%w") ~= nil

	-- deferOkuri で送り仮名が確定した直後 (▽おく*る) は、第一候補を
	-- 自動選択して即挿入する (completeopt の noselect をこの応答だけ外す)
	local auto_select = false
	if instant_insert and require("skkelua").phase() == "input:okuriari" then
		local state = require("skkelua.store").get_context().state
		auto_select = completion_config().deferOkuri and state.feed == "" and state.okuriFeed ~= ""
	end
	set_completeopt(0, auto_select)

	for _, item in ipairs(list.items) do
		if instant_insert then
			-- insertOnSelect: filterText を持たせないことで、クライアントの
			-- 挿入 word が newText (候補そのもの) になり、<C-n> での
			-- 選択と同時に pre-edit 全体が候補へ置き換わる
			item.filterText = nil
			if prefixed_label then
				item.data.display = item.label
				item.label = pre_edit .. item.label
			end
		else
			-- Note: PlainText だと word が filterText に fallback した場合に
			--       newText が適用されない (単なる再挿入になる)。
			--       Snippet format は確定時に挿入 word を削除して
			--       newText を展開するため、pre-edit を候補で置換できる
			item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
			item.textEdit.newText = escape_snippet(item.textEdit.newText)
		end
	end
	return list
end

--- 候補の確定 (workspace/executeCommand) を処理する。
--- クライアントは確定したときだけ item.command を実行するので、
--- <Esc>/<C-e> などで閉じた場合は何も起きない
---@param params {command: string, arguments?: table[]}
local function execute_command(params)
	if params.command ~= list_of.ACCEPT_COMMAND then
		-- level 0: クライアントへ返すエラーに位置情報を付けない
		error("unknown command: " .. tostring(params.command), 0)
	end
	local data = params.arguments and params.arguments[1]
	if not (data and data.skkelua) then
		return
	end
	if data.register then
		-- [辞書登録] 項目: 登録プロンプトを開く。サーバーはリクエストを
		-- vim.schedule で処理するので、補完の終了処理は既に抜けている。
		-- 挿入テキストが pre-edit のままなので
		-- handle 側では変換入力の続きとして registerWord が実行される
		require("skkelua").handle("handleKey", { ["function"] = "registerWord" })
		return
	end
	-- abbrev の raw 候補 (入力そのもの) は辞書へ登録しない
	if data.raw then
		return
	end
	require("skkelua").complete_callback(data.midasi, data.word, data.type)
end

--------------------------------------------------------------------
-- in-process server
--------------------------------------------------------------------

--- in-process サーバーの transport (vim.lsp.start の cmd)
---@param complete fun(params: table): table? textDocument/completion の応答。
---   nil は応答保留 (選択挿入中のバースト)
---@return fun(dispatchers: table): table
local function new_server(complete)
	return function(dispatchers)
		local closing = false
		local srv = {}
		local request_id = 0
		local function handle(method, params, handler)
			if method == "initialize" then
				handler(nil, {
					capabilities = {
						positionEncoding = "utf-8",
						completionProvider = {
							triggerCharacters = trigger_characters(),
						},
						executeCommandProvider = { commands = { list_of.ACCEPT_COMMAND } },
					},
				})
			elseif method == "textDocument/completion" then
				local ok, list = pcall(complete, params)
				if not ok then
					handler({ code = -32603, message = tostring(list) }, nil)
				elseif list then
					-- nil は応答保留 (選択挿入中のバースト)。放置されたリクエストは
					-- クライアントが次の trigger 時に cancel してくれる
					table.insert(M._requests, { params = params, items = #list.items })
					handler(nil, list)
				end
			elseif method == "workspace/executeCommand" then
				local ok, err = pcall(execute_command, params)
				handler(not ok and { code = -32603, message = tostring(err) } or nil, nil)
			elseif method == "shutdown" then
				handler(nil, nil)
			else
				-- 応答が無いとクライアントのリクエストが残り続ける
				handler(
					{ code = vim.lsp.protocol.ErrorCodes.MethodNotFound, message = "method not found: " .. method },
					nil
				)
			end
		end
		function srv.request(method, params, handler)
			request_id = request_id + 1
			vim.schedule(function()
				handle(method, params, handler)
			end)
			return true, request_id
		end
		function srv.notify(method, _)
			if method == "exit" then
				dispatchers.on_exit(0, 15)
			end
			return true
		end
		function srv.is_closing()
			return closing
		end
		function srv.terminate()
			closing = true
		end
		return srv
	end
end

--------------------------------------------------------------------
-- attach / detach
--------------------------------------------------------------------

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
end

--- 現在のバッファで補完を有効にする (skkelua-enable-post から呼ばれる)
function M.attach()
	if not completion_config().enabled then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local client_id = vim.lsp.start({
		name = CLIENT_NAME,
		cmd = new_server(make_completion_list),
		skkelua_builtin_completion = true,
	}, {
		bufnr = buf,
		-- 外部 UI 向けの共有クライアント (start) を組み込みの補完に流用しない
		reuse_client = function(client)
			return client.config.skkelua_builtin_completion == true and not client:is_stopped()
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

---@param buf integer
---@return vim.lsp.Client?
local function builtin_client(buf)
	for _, client in ipairs(vim.lsp.get_clients({ name = CLIENT_NAME, bufnr = buf })) do
		if client.config.skkelua_builtin_completion then
			return client
		end
	end
end

--- タイプを伴わずに pre-edit が復元された (辞書登録のキャンセルなど) ことを知らせる。
--- autotrigger はトリガー文字のタイプでしか働かないため、builtin の補完は
--- ここで明示的に再要求する。外部の補完 UI は User イベントで再要求する
function M.pre_edit_restored()
	pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "skkelua-pre-edit-restored", modeline = false })
	if not completion_config().enabled or vim.fn.mode() ~= "i" then
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	if not builtin_client(buf) then
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
	end
	restore_completeopt(buf)
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

--------------------------------------------------------------------
-- 外部の補完 UI 向け
--------------------------------------------------------------------

--- 補完要求の位置から、読み込み済みバッファ上の入力行を引く。
--- ドキュメントを開くことはしない。URI と入力先の対応づけは
--- この関数が担う範囲 (バッファ名 = URI) に限る
---@param params table textDocument/completion の params。character は UTF-8 のバイトオフセット
---@return {line: string, row: integer, col: integer}?
local function request_context(params)
	local uri = vim.tbl_get(params, "textDocument", "uri")
	local row = vim.tbl_get(params, "position", "line")
	local col = vim.tbl_get(params, "position", "character")
	if not (uri and row and col) then
		return nil
	end
	local function matches(bufnr)
		return vim.api.nvim_buf_is_loaded(bufnr) and vim.uri_from_bufnr(bufnr) == uri
	end
	-- 補完要求は打鍵ごとに届くので、多くの場合に当たる現在のバッファを先に調べ、
	-- 仮想ドキュメントなど現在のバッファでない場合だけ全バッファを走査する。
	-- 名前の無いバッファは全て同じ URI になるので、現在のバッファを先に調べる
	-- ことがそのまま要求元の特定になる (他の名前無しバッファと取り違えるのは
	-- 現在のバッファが要求元でない場合だけで、その行は pre-edit で終わらず
	-- 候補は出ない)
	local bufnr = vim.api.nvim_get_current_buf()
	if not matches(bufnr) then
		bufnr = nil
		for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
			if matches(candidate) then
				bufnr = candidate
				break
			end
		end
	end
	local line = bufnr and vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if line then
		return { line = line, row = row, col = col }
	end
end

--- 外部の補完 UI が使う LSP クライアントを、バッファに一度だけ attach する。
--- クライアントはバッファ間で共有され、SKK の有効・無効に関係なく残る。
--- 組み込みの補完 UI は有効化しない。候補は UI 非依存の形のまま返す
---@param bufnr? integer 省略時は現在のバッファ
---@return integer? client_id
function M.start(bufnr)
	if bufnr == nil or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, _uninitialized = true })) do
		if client.config.skkelua_external_completion and not client:is_stopped() then
			return client.id
		end
	end
	return vim.lsp.start({
		name = CLIENT_NAME,
		cmd = new_server(function(params)
			local context = request_context(params)
			return context and list_of.build(context) or { isIncomplete = true, items = {} }
		end),
		skkelua_external_completion = true,
	}, {
		bufnr = bufnr,
		reuse_client = function(client)
			return client.config.skkelua_external_completion == true and not client:is_stopped()
		end,
	})
end

--- テスト用: 確定コマンドを直接実行する
---@param params {command: string, arguments?: table[]}
function M._execute_command(params)
	execute_command(params)
end

--- テスト用: 任意のバッファへ attach できるトランスポート
function M._new_server()
	return new_server(make_completion_list)
end

--- テスト用: completion list を直接組み立てる
function M._make_completion_list()
	return make_completion_list()
end

-- テスト用: 処理した completion リクエストの記録
M._requests = {}

return M
