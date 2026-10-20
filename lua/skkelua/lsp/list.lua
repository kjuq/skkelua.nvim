-- 変換入力中の pre-edit から LSP の CompletionList を組み立てる。
-- 補完 UI には依存せず、UI 固有の整形 (insertOnSelect やスニペット化) は
-- 呼び出し側 (lsp.lua) が行う。

local M = {}

--- 候補の確定時にクライアントが実行するコマンド
M.ACCEPT_COMMAND = "skkelua.accept"

local candidates_of = require("skkelua.lsp.candidates")

local function completion_config()
	return require("skkelua.config").config.completion
end

--- 新しい読みを登録する項目の見出し。登録する読みが定まらない間は nil
---@param phase string
---@return string?
local function register_midasi(phase)
	local state = require("skkelua.store").get_context().state
	if phase == "henkan" then
		return state.word
	elseif phase == "input:okuriari" then
		-- 送り仮名が確定するまでは登録する読みが定まらない
		if state.feed == "" and state.okuriFeed ~= "" then
			return require("skkelua.okuri").get_okuri_str(state.henkanFeed, state.okuriFeed)
		end
		return nil
	end
	return state.henkanFeed
end

--- 確定時に辞書学習や登録プロンプトを起動するための command を付ける。
--- クライアントは確定した時だけ実行するため、キャンセルでは何も起きない
---@param item table CompletionItem
local function with_command(item)
	item.command = { title = "skkelua", command = M.ACCEPT_COMMAND, arguments = { item.data } }
	return item
end

--- 補完候補を組み立てる。位置は 0 始まりの UTF-8 バイトオフセット
---@param context {line: string, row: integer, col: integer}
---@return table list CompletionList
---@return "inactive"|"stale"? reason 変換入力中でなければ "inactive"、
---   カーソル前のテキストが pre-edit で終わっていなければ "stale"
function M.build(context)
	local empty = { isIncomplete = true, items = {} }
	local skkelua = require("skkelua")
	local phase = skkelua.phase()
	local supported = phase == "input:okurinasi" or phase == "input:okuriari" or phase == "henkan"
	if not skkelua.is_enabled() or not supported then
		return empty, "inactive"
	end
	local pre_edit = skkelua.get_pre_edit()
	-- 変換入力中はかなが無ければ出さない (henkan は候補が引けているので不要)
	if pre_edit == "" or (phase ~= "henkan" and skkelua.get_prefix() == "") then
		return empty, "inactive"
	end

	-- カーソル前のテキストが pre-edit (▽かんじ) で終わっていることを確認し、
	-- その開始位置を置換範囲にする
	local row, col, line = context.row, context.col, context.line
	if not vim.endswith(line:sub(1, col), pre_edit) then
		return empty, "stale"
	end
	local range = {
		start = { line = row, character = col - #pre_edit },
		["end"] = { line = row, character = col },
	}

	local marker = require("skkelua.config").config.markerHenkan
	local modify_candidate = require("skkelua.candidate").modify_candidate

	local candidates
	if phase == "input:okurinasi" then
		candidates = candidates_of.okurinasi()
	elseif phase == "input:okuriari" then
		candidates = candidates_of.okuriari()
	else
		candidates = candidates_of.henkan()
	end

	local items = {}
	-- abbrev の raw 候補のうち入力そのもの (abbrevWithSpace = false) は
	-- 辞書候補ではないので [辞書登録] より後ろに回す。スペース前置形は
	-- 英単語をそのまま入れる主用途なので [辞書登録] より前に置く
	local raw_trailing = not completion_config().abbrevWithSpace
	local trailing = {}
	local seen = {}
	for _, c in ipairs(candidates) do
		-- 送りありは語幹 + 送り仮名の完成形を挿入する
		local display = (modify_candidate(c.word, c.affix) or c.word) .. c.okuri
		if not seen[display] then
			seen[display] = true
			local annotation = c.word:match(";(.*)$")
			local item = {
				label = display,
				labelDetails = annotation and { description = annotation } or nil,
				detail = c.midasi,
				kind = vim.lsp.protocol.CompletionItemKind.Text,
				-- クライアントは typed text と filterText を照合する。
				-- 送りなし入力中は続きのかな入力で絞り込めるよう marker + 見出し、
				-- それ以外 (送りあり入力・候補選択) は pre-edit そのもの
				-- (絞り込みは isIncomplete の再リクエストが担う)
				filterText = phase == "input:okurinasi" and (marker .. c.midasi) or pre_edit,
				insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
				textEdit = {
					range = range,
					newText = display,
				},
				-- okuri (送り仮名の生かな) は purgeCandidate が ▽henkanFeed*okuriFeed
				-- を組み立て直すのに使う (midasi は語幹 + 送り仮名アルファベットの
				-- 辞書見出し形式で、そのままでは送り仮名を分離できない)。
				-- text は確定時にバッファへ入れる文字列 (init.lua の finalize_completion)
				data = {
					skkelua = true,
					midasi = c.midasi,
					word = c.word,
					type = c.type,
					okuri = c.okuri,
					raw = c.raw,
					text = display,
				},
			}
			with_command(item)
			if c.raw and raw_trailing then
				trailing[#trailing + 1] = item
			else
				items[#items + 1] = item
			end
		end
	end

	-- 新しい読みを登録する項目を辞書候補の後ろに置く (候補が無い読みでも pum が開く)。
	-- 挿入テキストは pre-edit 自身にして、フォーカスや確定でバッファが
	-- 変わらないようにする。確定すると登録プロンプトが開く
	-- (登録プロンプトの中ではネストしたプロンプトが積まれる)。
	local midasi = register_midasi(phase)
	if midasi then
		items[#items + 1] = with_command({
			label = "[辞書登録]",
			detail = midasi,
			kind = vim.lsp.protocol.CompletionItemKind.Text,
			filterText = pre_edit,
			insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
			textEdit = {
				range = range,
				newText = pre_edit,
			},
			data = { skkelua = true, register = true, text = pre_edit },
		})
	end
	vim.list_extend(items, trailing)

	-- クライアントは sortText (無ければ label) で並べ替える。
	-- 辞書順 (ユーザー辞書 -> グローバル辞書のマージ順) と上の配置を保つよう
	-- 応答順の連番を振る
	for i, item in ipairs(items) do
		item.sortText = ("%05d"):format(i)
	end

	return { isIncomplete = true, items = items }
end

return M
