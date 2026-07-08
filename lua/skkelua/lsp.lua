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

--- vim.snippet の特殊文字 ($ と \) をエスケープする
---@param s string
---@return string
local function escape_snippet(s)
	return (s:gsub("[\\%$]", "\\%0"))
end

--- ひらがな (+ 長音・マーカー) を triggerCharacters として列挙する
---@return string[]
local function trigger_characters()
	local chars = {}
	-- ぁ (U+3041) 〜 ゖ (U+3096)
	for cp = 0x3041, 0x3096 do
		chars[#chars + 1] = vim.fn.nr2char(cp)
	end
	chars[#chars + 1] = "ー"
	chars[#chars + 1] = require("skkelua.config").config.markerHenkan
	return chars
end

---@class skkelua.LspCandidate
---@field word string 辞書上の候補原文 (注釈付き)
---@field midasi string 辞書の見出し
---@field okuri string 送り仮名 (送りなしは "")
---@field type skkelua.HenkanType

--- 送りなし変換入力 (▽かんじ) の候補: 見出しの前方一致検索
---@return skkelua.LspCandidate[]
local function okurinasi_candidates()
	local skkelua = require("skkelua")
	local result = {}
	for _, entry in ipairs(skkelua.get_completion_result()) do
		local midasi, words = entry[1], entry[2]
		for _, word in ipairs(words) do
			result[#result + 1] = { word = word, midasi = midasi, okuri = "", type = "okurinasi" }
		end
	end
	return result
end

--- feed (送りのローマ字) から確定しうる送り仮名を列挙する
---@param kana_table skkelua.KanaTable
---@param feed string
---@return string[]
local function feed_kana_candidates(kana_table, feed)
	local kanas = {}
	local seen = {}
	for _, e in ipairs(kana_table) do
		-- feed に前方一致し、残余 feed を持たないエントリだけが送り仮名として完成する
		if vim.startswith(e[1], feed) and type(e[2]) == "table" and e[2][2] == "" then
			local kana = e[2][1]
			if kana ~= "" and not seen[kana] then
				seen[kana] = true
				kanas[#kanas + 1] = kana
			end
		end
	end
	return kanas
end

--- 送りあり変換入力 (▽おく*r) の候補:
--- 送りのローマ字からありうる送り仮名を列挙し、語幹 + 送り仮名の完成形を出す
---@return skkelua.LspCandidate[]
local function okuriari_candidates()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "input" or state.previousFeed then
		return {}
	end
	local lib = require("skkelua.store").get_library()
	local get_okuri_str = require("skkelua.okuri").get_okuri_str

	local result = {}
	local function collect(midasi, okuri)
		for _, word in ipairs(lib:get_henkan_result("okuriari", midasi)) do
			result[#result + 1] = { word = word, midasi = midasi, okuri = okuri, type = "okuriari" }
		end
	end

	if state.okuriFeed ~= "" then
		-- 送り仮名の先頭が確定済み (immediatelyOkuriConvert=false の「っ」など)。
		-- 見出しは確定しているので、残り feed の展開だけ行う
		local midasi = get_okuri_str(state.henkanFeed, state.okuriFeed)
		if state.feed == "" then
			collect(midasi, state.okuriFeed)
		else
			for _, kana in ipairs(feed_kana_candidates(state.table, state.feed)) do
				collect(midasi, state.okuriFeed .. kana)
			end
		end
	elseif state.feed ~= "" then
		for _, kana in ipairs(feed_kana_candidates(state.table, state.feed)) do
			collect(get_okuri_str(state.henkanFeed, kana), kana)
		end
	end
	return result
end

--- 補完候補を組み立てる
---@param params table textDocument/completion のパラメータ
---@return table CompletionList
local function make_completion_list(params)
	local empty = { isIncomplete = true, items = {} }
	local skkelua = require("skkelua")
	local phase = skkelua.phase()
	if not skkelua.is_enabled() or (phase ~= "input:okurinasi" and phase ~= "input:okuriari") then
		return empty
	end
	local pre_edit = skkelua.get_pre_edit()
	local prefix = skkelua.get_prefix()
	if pre_edit == "" or prefix == "" then
		return empty
	end

	-- カーソル前のテキストが pre-edit (▽かんじ) で終わっていることを確認し、
	-- その開始位置を置換範囲にする
	local row = params.position and params.position.line
	local col = params.position and params.position.character -- utf-8 (byte)
	if not (row and col) then
		return empty
	end
	local buf = vim.api.nvim_get_current_buf()
	local line = (vim.api.nvim_buf_get_lines(buf, row, row + 1, false) or {})[1] or ""
	local before_cursor = line:sub(1, col)
	if not vim.endswith(before_cursor, pre_edit) then
		return empty
	end
	local start_col = col - #pre_edit
	local range = {
		start = { line = row, character = start_col },
		["end"] = { line = row, character = col },
	}

	local marker = require("skkelua.config").config.markerHenkan
	local modify_candidate = require("skkelua.candidate").modify_candidate

	-- ユーザー辞書のランク (新しく使った候補ほど大きい値) を sortText へ反映する
	local ranks = {}
	for _, e in ipairs(skkelua.get_ranks()) do
		ranks[e[1]] = e[2]
	end

	local candidates
	if phase == "input:okurinasi" then
		candidates = okurinasi_candidates()
	else
		candidates = okuriari_candidates()
	end

	local items = {}
	local seen = {}
	for _, c in ipairs(candidates) do
		-- 送りありは語幹 + 送り仮名の完成形を挿入する
		local display = (modify_candidate(c.word) or c.word) .. c.okuri
		if not seen[display] then
			seen[display] = true
			local annotation = c.word:match(";(.*)$")
			local rank = ranks[c.word]
			local sort_text
			if rank then
				-- ランク付きを先頭に、ランクが大きい (新しい) ほど前へ
				sort_text = ("0%015d"):format(1e15 - rank)
			else
				sort_text = ("1%08d"):format(#items)
			end
			items[#items + 1] = {
				label = display,
				labelDetails = annotation and { description = annotation } or nil,
				detail = c.midasi,
				kind = vim.lsp.protocol.CompletionItemKind.Text,
				-- クライアントは typed text と filterText を照合する。
				-- 送りなしは続きのかな入力で絞り込めるよう marker + 見出し、
				-- 送りありは pre-edit そのもの (絞り込みは再リクエストが担う)
				filterText = c.type == "okurinasi" and (marker .. c.midasi) or pre_edit,
				sortText = sort_text,
				-- Note: PlainText だと word が filterText に fallback した場合に
				--       newText が適用されない (単なる再挿入になる)。
				--       Snippet format は確定時に挿入 word を削除して
				--       newText を展開するため、pre-edit を候補で置換できる
				insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
				textEdit = {
					range = range,
					newText = escape_snippet(display),
				},
				data = { skkelua = true, midasi = c.midasi, word = c.word, type = c.type },
			}
		end
	end
	return { isIncomplete = true, items = items }
end

--------------------------------------------------------------------
-- in-process server
--------------------------------------------------------------------

---@return fun(dispatchers: table): table
local function new_server()
	return function(dispatchers)
		local closing = false
		local srv = {}
		srv.request = vim.schedule_wrap(function(method, params, handler)
			if method == "initialize" then
				handler(nil, {
					capabilities = {
						positionEncoding = "utf-8",
						completionProvider = {
							triggerCharacters = trigger_characters(),
						},
					},
				})
			elseif method == "textDocument/completion" then
				local list = make_completion_list(params)
				table.insert(M._requests, { params = params, items = #list.items })
				handler(nil, list)
			elseif method == "shutdown" then
				handler(nil, nil)
			end
		end)
		function srv.notify(method, _)
			if method == "exit" then
				dispatchers.on_exit(0, 15)
			end
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

--- 候補確定時にユーザー辞書へ登録する
local function on_complete_done()
	local item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item")
	local data = item and item.data
	if data and data.skkelua then
		require("skkelua").complete_callback(data.midasi, data.word, data.type)
	end
end

---@param client_id integer
---@param buf integer
local function enable_completion(client_id, buf)
	vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true })
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
	}, { bufnr = buf })
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

--- 現在のバッファで補完を無効にする (skkelua-disable-post から呼ばれる)
function M.detach()
	local buf = vim.api.nvim_get_current_buf()
	local client = vim.lsp.get_clients({ name = CLIENT_NAME, bufnr = buf })[1]
	if client then
		vim.lsp.completion.enable(false, client.id, buf)
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
			if client and client.name == CLIENT_NAME then
				enable_completion(ev.data.client_id, ev.buf)
			end
		end,
	})
end

--- テスト用: completion list を直接組み立てる
function M._make_completion_list(params)
	return make_completion_list(params)
end

-- テスト用: 処理した completion リクエストの記録
M._requests = {}

return M
