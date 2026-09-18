-- UI-independent SKK completion. Positions are zero-based UTF-8 byte offsets.
local M = {}
local adapter

---@class skkelua.CompletionSelection
---@field word string Text currently inserted by selection (empty if not inserted)
---@field item table Original LSP CompletionItem, including data
---@class skkelua.CompletionAdapter
---@field state fun(): {visible: boolean, selected?: skkelua.CompletionSelection}
---@field confirm fun(): string Keys to confirm selection; must not mutate text synchronously
---@field trigger? fun() Request completion after pre-edit restoration

--- Install one UI adapter. Pass nil to restore automatic completion handling.
--- The adapter owns its UI, lifecycle, item conversion and acceptance events.
---@param value? skkelua.CompletionAdapter
function M.set_adapter(value)
	adapter = value
end

local function effective_adapter()
	if adapter then
		return adapter
	end
	return require("skkelua.completion.builtin").detect()
end

---@return table? state nil means the native UI owns completion
function M.state()
	local active = effective_adapter()
	return active and active.state() or nil
end

function M.confirm()
	local active = effective_adapter()
	return active and active.confirm() or nil
end

---@return boolean handled
function M.trigger()
	if not adapter then
		return false
	end
	if adapter.trigger then
		adapter.trigger()
	end
	return true
end

function M.visible()
	local state = M.state()
	if state then
		return state.visible == true
	end
	return vim.fn.pumvisible() == 1
end

function M.is_register_item(item)
	local data = item and item.data
	return type(data) == "table" and data.skkelua == true and data.register == true
end

---@class skkelua.LspCandidate
---@field word string 辞書上の候補原文 (注釈付き)
---@field midasi string 辞書の見出し
---@field okuri string 送り仮名 (送りなしは "")
---@field type skkelua.HenkanType
---@field affix? skkelua.AffixType
---@field rank? number 並び順の決定に使うランク (大きいほど上)
---@field raw? boolean 辞書由来でない候補 (abbrev の半角スペース + 入力。登録・purge の対象外)

--- 送りなし変換入力 (▽かんじ) の候補: 見出しの前方一致検索
--- ユーザー辞書で確定済みの候補 (ランク持ち) を確定が新しい順に先頭へ置き、
--- 残りは見出しの辞書順で並べる。
--- abbrev モードでは入力の半角スペース前置形を末尾に足す
---@return skkelua.LspCandidate[]
local function okurinasi_candidates()
	local skkelua = require("skkelua")
	local completions = skkelua.get_completion_result()
	table.sort(completions, function(a, b)
		return a[1] < b[1]
	end)
	local ranks = {}
	for _, e in ipairs(skkelua.get_ranks()) do
		ranks[e[1]] = e[2]
	end
	-- ランクを持たない候補はランク持ちの末尾より配置する。
	-- 見出しの辞書順を保つよう先頭から順に負の方向にランクを振っていく
	local global_rank = -1
	local result = {}
	for _, entry in ipairs(completions) do
		local midasi, words = entry[1], entry[2]
		for _, word in ipairs(words) do
			local rank = ranks[word]
			if rank == nil then
				rank = global_rank
				global_rank = global_rank - 1
			end
			result[#result + 1] = { word = word, midasi = midasi, okuri = "", type = "okurinasi", rank = rank }
		end
	end
	table.sort(result, function(a, b)
		return a.rank > b.rank
	end)
	local context = require("skkelua.store").get_context()
	if context.mode == "abbrev" then
		-- 入力したアルファベットの前に半角スペースを足したもの (英単語を
		-- 和文の中に空けて入れる用)。入力そのものは <C-y> の無変換確定で
		-- 入るので候補には並べない
		local feed = context.state.henkanFeed
		result[#result + 1] = { word = " " .. feed, midasi = feed, okuri = "", type = "okurinasi", raw = true }
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

--- 候補選択中 (▼送る) の候補: 引いてある変換候補をそのまま並べる
---@return skkelua.LspCandidate[]
local function henkan_candidates()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "henkan" then
		return {}
	end
	local okuri = state.converter and state.converter(state.okuriFeed) or state.okuriFeed
	local result = {}
	for _, word in ipairs(state.candidates) do
		result[#result + 1] = {
			word = word,
			midasi = state.word,
			okuri = okuri,
			type = state.mode,
			affix = state.affix,
		}
	end
	return result
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

---@param context {line: string, row: integer, col: integer}
---@return table CompletionList
function M.get(context)
	local empty = { isIncomplete = true, items = {} }
	local skkelua = require("skkelua")
	local phase = skkelua.phase()
	local supported = phase == "input:okurinasi" or phase == "input:okuriari" or phase == "henkan"
	if not skkelua.is_enabled() or not supported then
		return empty
	end
	local pre_edit = skkelua.get_pre_edit()
	-- 変換入力中はかなが無ければ出さない (henkan は候補が引けているので不要)
	if pre_edit == "" or (phase ~= "henkan" and skkelua.get_prefix() == "") then
		return empty
	end

	local row, col, line = context.row, context.col, context.line
	if row < 0 or col < 0 or col > #line or not vim.endswith(line:sub(1, col), pre_edit) then
		return empty
	end
	local start_col = col - #pre_edit
	local range = {
		start = { line = row, character = start_col },
		["end"] = { line = row, character = col },
	}

	local marker = require("skkelua.config").config.markerHenkan
	local modify_candidate = require("skkelua.candidate").modify_candidate

	local candidates
	if phase == "input:okurinasi" then
		candidates = okurinasi_candidates()
	elseif phase == "input:okuriari" then
		candidates = okuriari_candidates()
	else
		candidates = henkan_candidates()
	end

	local items = {}
	local seen = {}
	for _, c in ipairs(candidates) do
		-- 送りありは語幹 + 送り仮名の完成形を挿入する
		local display = (modify_candidate(c.word, c.affix) or c.word) .. c.okuri
		if not seen[display] then
			seen[display] = true
			local annotation = c.word:match(";(.*)$")
			local item = {
				label = display,
				insertText = display,
				labelDetails = annotation and { description = annotation } or nil,
				detail = c.midasi,
				kind = vim.lsp.protocol.CompletionItemKind.Text,
				-- クライアントは sortText (無ければ label) で並べ替える。
				-- 辞書順 (ユーザー辞書 -> グローバル辞書のマージ順) を保つよう
				-- 応答順の連番を振る
				sortText = ("%05d"):format(#items + 1),
				textEdit = {
					range = range,
					newText = display,
				},
				-- okuri (送り仮名の生かな) は purgeCandidate が ▽henkanFeed*okuriFeed
				-- を組み立て直すのに使う (midasi は語幹 + 送り仮名アルファベットの
				-- 辞書見出し形式で、そのままでは送り仮名を分離できない)
				data = { skkelua = true, midasi = c.midasi, word = c.word, type = c.type, okuri = c.okuri, raw = c.raw },
			}
			item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText
			item.filterText = phase == "input:okurinasi" and (marker .. c.midasi) or pre_edit
			items[#items + 1] = item
		end
	end

	-- 新しい読みを登録する項目を末尾に置く (候補が無い読みでも pum が開く)。
	-- 挿入テキストは pre-edit 自身にして、フォーカスや確定でバッファが
	-- 変わらないようにする。確定時の accept() から登録プロンプトが開く
	-- (登録プロンプトの中ではネストしたプロンプトが積まれる)。
	local state = require("skkelua.store").get_context().state
	local registrable = true
	local midasi
	if phase == "henkan" then
		midasi = state.word
	elseif phase == "input:okuriari" then
		-- 送り仮名が確定するまでは登録する読みが定まらない
		registrable = registrable and state.feed == "" and state.okuriFeed ~= ""
		midasi = registrable and require("skkelua.okuri").get_okuri_str(state.henkanFeed, state.okuriFeed)
	else
		midasi = state.henkanFeed
	end
	if registrable then
		local item = {
			label = "[辞書登録]",
			insertText = pre_edit,
			detail = midasi,
			kind = vim.lsp.protocol.CompletionItemKind.Text,
			sortText = ("%05d"):format(#items + 1),
			textEdit = {
				range = range,
				newText = pre_edit,
			},
			data = { skkelua = true, register = true },
		}
		item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText
		item.filterText = pre_edit
		items[#items + 1] = item
	end

	return { isIncomplete = true, items = items }
end

--- Call once after accepting an item, never on selection or cancellation.
--- The consumer applies textEdit and retains the original item's data.
---@param item table LSP CompletionItem
---@return boolean handled
function M.accept(item)
	local data = item and item.data
	if not (data and data.skkelua) then
		return false
	end
	if data.register then
		-- [辞書登録] 項目: ins-completion の終了処理から抜けてから
		-- 登録プロンプトを開く。挿入テキストが pre-edit のままなので
		-- handle 側では変換入力の続きとして registerWord が実行される
		vim.schedule(function()
			require("skkelua").handle("handleKey", { ["function"] = "registerWord" })
		end)
		return true
	end
	-- abbrev の raw 候補 (半角スペース + 入力) は辞書へ登録しない
	if data.raw then
		return true
	end
	require("skkelua").complete_callback(data.midasi, data.word, data.type)
	return true
end

return M
