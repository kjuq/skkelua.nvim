-- 外部の補完 UI 向け共有クライアント (lsp.start) のテスト

local t = require("tests.helper")

local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }

--- ▽かんじ を置いたバッファを作る。name が無ければ名前の無いバッファ
---@param name? string
---@return integer bufnr
local function setup_henkan_buffer(name)
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	local skkelua = require("skkelua")
	skkelua._handle_request("enable", {}, vim_status)
	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		skkelua._handle_request("handleKey", { key = { k } }, {
			mode = "",
			prevInput = require("skkelua.store").get_context():to_string(),
			completeInfo = {},
			completeType = "",
		})
	end
	t.assert_equals("▽かんじ", skkelua.get_pre_edit())
	vim.cmd.enew({ bang = true })
	local buf = vim.api.nvim_get_current_buf()
	if name then
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "-" .. name)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "▽かんじ" })
	return buf
end

---@param buf integer
---@return vim.lsp.Client
local function started_client(buf)
	local id = require("skkelua.lsp").start(buf)
	local client = assert(vim.lsp.get_client_by_id(id))
	t.assert_true(vim.wait(1000, function()
		return client.initialized
	end))
	return client
end

--- 同期的に textDocument/completion を要求する
---@param client vim.lsp.Client
---@param buf integer
---@param character integer
local function request_completion(client, buf, character)
	local result
	client:request("textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 0, character = character },
	}, function(_, res)
		result = res or false
	end, buf)
	t.assert_true(vim.wait(1000, function()
		return result ~= nil
	end))
	return result
end

local function cleanup(...)
	for _, client in ipairs({ ... }) do
		client:stop(true)
	end
	vim.cmd.bwipeout({ bang = true })
end

t.test("start shares one client across buffers and calls", function()
	local first = setup_henkan_buffer("a")
	local client = started_client(first)
	t.assert_equals(client.id, require("skkelua.lsp").start(first))

	vim.cmd.enew({ bang = true })
	local second = vim.api.nvim_get_current_buf()
	t.assert_equals(client.id, require("skkelua.lsp").start(second))
	t.assert_true(vim.lsp.buf_is_attached(first, client.id))
	t.assert_true(vim.lsp.buf_is_attached(second, client.id))
	vim.cmd.bwipeout({ bang = true })
	cleanup(client)
end)

t.test("start's client reports the request as sent with an id and can cancel it", function()
	-- 戻り値で送信の成否を判断するクライアントは、id が無いと結果を捨てる。builtin の補完は見ないので別に確認する
	local buf = setup_henkan_buffer("sent")
	local client = started_client(buf)
	local ok, id = client:request("textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 0, character = #"▽かんじ" },
	}, function() end, buf)
	t.assert_equals(true, ok)
	t.assert_true(type(id) == "number")
	t.assert_equals(true, client:cancel_request(id))
	cleanup(client)
end)

t.test("start returns a UI-independent list for the requested position", function()
	local buf = setup_henkan_buffer("b")
	local client = started_client(buf)
	local list = request_completion(client, buf, #"▽かんじ")

	t.assert_equals(
		{ "漢字", "[辞書登録]" },
		vim.tbl_map(function(item)
			return item.label
		end, list.items)
	)
	-- 組み込みメニュー向けの整形 (スニペット化・filterText の除去) はしない
	local item = list.items[1]
	t.assert_equals(vim.lsp.protocol.InsertTextFormat.PlainText, item.insertTextFormat)
	t.assert_equals("漢字", item.textEdit.newText)
	t.assert_equals("▽かんじ", item.filterText)
	t.assert_equals("skkelua.accept", item.command.command)
	cleanup(client)
end)

t.test("start serves the current buffer even when it has no name", function()
	-- 名前の無いバッファは全て同じ URI になるため、現在のバッファを要求元とみなす
	local buf = setup_henkan_buffer()
	t.assert_equals("", vim.api.nvim_buf_get_name(buf))
	local client = started_client(buf)
	local list = request_completion(client, buf, #"▽かんじ")
	t.assert_equals(
		{ "漢字", "[辞書登録]" },
		vim.tbl_map(function(item)
			return item.label
		end, list.items)
	)
	cleanup(client)
end)

t.test("start returns nothing for unknown documents and stale positions", function()
	local buf = setup_henkan_buffer("c")
	local client = started_client(buf)
	local unknown = {}
	client:request("textDocument/completion", {
		textDocument = { uri = "file:///no/such/document" },
		position = { line = 0, character = 0 },
	}, function(_, res)
		unknown.result = res
	end, buf)
	t.assert_true(vim.wait(1000, function()
		return unknown.result ~= nil
	end))
	t.assert_equals(0, #unknown.result.items)
	-- カーソル前のテキストが pre-edit で終わらない位置では候補を出さない
	t.assert_equals(0, #request_completion(client, buf, #"▽か").items)
	cleanup(client)
end)

--- buf に attach されている builtin 用のクライアント
local function builtin_client(buf)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, name = "skkelua" })) do
		if client.config.skkelua_builtin_completion then
			return client
		end
	end
end

t.test("start keeps its client apart from the builtin one in either order", function()
	local buf = setup_henkan_buffer("d")
	require("skkelua").config({ completion = { enabled = true } })
	-- 停止済み (終了通知待ち) のクライアントは数えない
	t.assert_equals(0, #vim.tbl_filter(function(client)
		return not client:is_stopped()
	end, vim.lsp.get_clients({ name = "skkelua" })))

	-- external -> builtin
	local external = started_client(buf)
	require("skkelua.lsp").attach()
	t.assert_true(vim.wait(1000, function()
		return builtin_client(buf) ~= nil
	end))
	local builtin = assert(builtin_client(buf))
	t.assert_true(external.id ~= builtin.id)
	t.assert_equals(nil, external.config.skkelua_builtin_completion)
	t.assert_equals(external.id, require("skkelua.lsp").start(buf))
	cleanup(external, builtin)

	-- builtin -> external
	buf = setup_henkan_buffer("d2")
	require("skkelua.lsp").attach()
	t.assert_true(vim.wait(1000, function()
		return builtin_client(buf) ~= nil
	end))
	builtin = assert(builtin_client(buf))
	external = started_client(buf)
	t.assert_true(external.id ~= builtin.id)
	t.assert_equals(true, external.config.skkelua_external_completion)
	cleanup(external, builtin)
end)

t.test("start uses the current buffer by default and restarts after the client stops", function()
	local buf = setup_henkan_buffer("g")
	local client = started_client(buf)
	t.assert_equals(client.id, require("skkelua.lsp").start())
	t.assert_equals(client.id, require("skkelua.lsp").start(0))

	client:stop(true)
	t.assert_true(vim.wait(1000, function()
		return client:is_stopped()
	end))
	local restarted = started_client(buf)
	t.assert_true(restarted.id ~= client.id)
	cleanup(restarted)
end)

t.test("start's client stays attached after SKK is disabled", function()
	local buf = setup_henkan_buffer("h")
	local client = started_client(buf)
	require("skkelua")._handle_request("disable", {}, vim_status)
	t.assert_true(vim.lsp.buf_is_attached(buf, client.id))
	t.assert_equals(false, client:is_stopped())
	cleanup(client)
end)

--- 同期的にリクエストし、(err, result) を返す
---@param client vim.lsp.Client
---@param buf integer
---@param method string
---@param params table
local function request(client, buf, method, params)
	local done, err, result = false, nil, nil
	client:request(method, params, function(e, r)
		done, err, result = true, e, r
	end, buf)
	t.assert_true(
		vim.wait(1000, function()
			return done
		end),
		method .. " was never answered"
	)
	return err, result
end

t.test("the server answers requests it cannot serve", function()
	local buf = setup_henkan_buffer("e")
	local client = started_client(buf)

	local err = request(client, buf, "completionItem/resolve", { label = "x" })
	t.assert_equals(vim.lsp.protocol.ErrorCodes.MethodNotFound, err.code)

	-- position の無い補完要求も応答を返す (候補は無い)
	local _, list = request(client, buf, "textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
	})
	t.assert_equals(0, #list.items)

	err = request(client, buf, "workspace/executeCommand", { command = "no.such.command" })
	t.assert_equals(-32603, err.code)
	t.assert_equals("unknown command: no.such.command", err.message)
	cleanup(client)
end)

t.test("start finds the requested document when it is not the current buffer", function()
	local buf = setup_henkan_buffer("f")
	local client = started_client(buf)
	vim.cmd.enew({ bang = true })
	local list = request_completion(client, buf, #"▽かんじ")
	t.assert_equals(2, #list.items)
	vim.cmd.bwipeout({ bang = true })
	vim.api.nvim_buf_delete(buf, { force = true })
	client:stop(true)
end)
