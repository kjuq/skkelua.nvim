-- in-process LSP サーバーが返す変換候補の生成 (UI・transport に依存しない)

local M = {}

---@class skkelua.LspCandidate
---@field word string 辞書上の候補原文 (注釈付き)
---@field midasi string 辞書の見出し
---@field okuri string 送り仮名 (送りなしは "")
---@field type skkelua.HenkanType
---@field affix? skkelua.AffixType
---@field rank? number 並び順の決定に使うランク (大きいほど上)
---@field raw? boolean 辞書由来でない候補 (abbrev の入力そのまま。completion.abbrevWithSpace で半角スペースを前置できる。登録・purge の対象外)

--- 送りなし変換入力 (▽かんじ) の候補: 見出しの前方一致検索
--- (@ddc-sources/skkeleton の gather に相当)。
--- ユーザー辞書で確定済みの候補 (ランク持ち) を確定が新しい順に先頭へ置き、
--- 残りは見出しの辞書順で並べる。
--- abbrev モードでは入力の raw 候補を末尾に足す
--- (補完リストではスペース前置形は [辞書登録] の前、
--- abbrevWithSpace = false の入力そのままは [辞書登録] の後ろに並ぶ)
---@return skkelua.LspCandidate[]
function M.okurinasi()
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
		-- 入力そのものの raw 候補。completion.abbrevWithSpace (デフォルト true) だと
		-- 前に半角スペースを足す (英単語を和文の中に空けて入れる用)。false なら
		-- 入力そのまま (▽overall なら "overall")
		local feed = context.state.henkanFeed
		local with_space = require("skkelua.config").config.completion.abbrevWithSpace
		local word = with_space and (" " .. feed) or feed
		result[#result + 1] = { word = word, midasi = feed, okuri = "", type = "okurinasi", raw = true }
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
function M.henkan()
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
function M.okuriari()
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

return M
