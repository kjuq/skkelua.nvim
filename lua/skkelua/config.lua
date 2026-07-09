-- 設定管理 (config.ts に相当)

local util = require("skkelua.util")

local M = {}

---@class skkelua.IndicatorOptions
---@field enabled boolean
---@field eijiText string
---@field hiraText string
---@field kataText string
---@field hankataText string
---@field zenkakuText string
---@field abbrevText string
---@field eijiHlName string
---@field hiraHlName string
---@field kataHlName string
---@field hankataHlName string
---@field zenkakuHlName string
---@field abbrevHlName string
---@field border? string|string[]|fun(args: { mode: string }): any
---@field row? integer nil なら border に応じて自動 (border なし: 1 / あり: 0)
---@field col integer
---@field zindex? integer
---@field alwaysShown boolean
---@field fadeOutMs integer
---@field ignoreFt string[]
---@field bufFilter? fun(buf: integer): boolean
---@field useDefaultHighlight boolean
local default_indicator = {
	enabled = true,
	eijiText = "英字",
	hiraText = "ひら",
	kataText = "カタ",
	hankataText = "半ｶﾀ",
	zenkakuText = "全英",
	abbrevText = "abbr",
	eijiHlName = "SkkeluaIndicatorEiji",
	hiraHlName = "SkkeluaIndicatorHira",
	kataHlName = "SkkeluaIndicatorKata",
	hankataHlName = "SkkeluaIndicatorHankata",
	zenkakuHlName = "SkkeluaIndicatorZenkaku",
	abbrevHlName = "SkkeluaIndicatorAbbrev",
	border = nil,
	row = nil,
	col = 1,
	zindex = nil,
	alwaysShown = true,
	fadeOutMs = 3000,
	ignoreFt = {},
	bufFilter = nil,
	useDefaultHighlight = true,
}

M.default_indicator = default_indicator

---@class skkelua.CompletionOptions
---@field enabled boolean 変換候補を builtin LSP 補完として表示するかどうか
---@field insertOnSelect boolean 候補の選択 (フォーカス) と同時に本文へ挿入するかどうか
---@field deferOkuri boolean 送り仮名確定時に自動変換せず、補完メニューでの選択に委ねるかどうか
local default_completion = {
	enabled = false,
	insertOnSelect = false,
	deferOkuri = false,
}

M.default_completion = default_completion

---@class skkelua.ConfigOptions
M.config = {
	acceptIllegalResult = false,
	---@type skkelua.CompletionOptions
	completion = vim.deepcopy(default_completion),
	completionRankFile = "",
	databasePath = "",
	debug = false,
	eggLikeNewline = false,
	---@type (string|[string, string])[] normalize 後は [string, string][]
	globalDictionaries = {},
	---@type (string|[string, string])[]
	globalKanaTableFiles = {},
	immediatelyCancel = true,
	immediatelyDictionaryRW = true,
	immediatelyOkuriConvert = true,
	---@type skkelua.IndicatorOptions
	indicator = vim.deepcopy(default_indicator),
	kanaTable = "rom",
	keepMode = false,
	keepState = false,
	---@type table<string, string>
	lowercaseMap = {},
	---@type string[]? nil ならデフォルトキー (require("skkelua").get_default_mapped_keys())
	mappedKeys = nil,
	markerHenkan = "▽",
	markerHenkanSelect = "▼",
	registerConvertResult = false,
	selectCandidateKeys = "asdfjkl",
	setUndoPoint = true,
	showCandidatesCount = 4,
	skkServerHost = "127.0.0.1",
	skkServerPort = 1178,
	skkServerReqEnc = "euc-jp",
	skkServerResEnc = "euc-jp",
	sources = { "skk_dictionary" },
	-- $XDG_DATA_HOME/nvim/skkelua/jisyo (stdpath が ~/.local/share への
	-- フォールバックを内蔵している)
	userDictionary = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "skkelua", "jisyo"),
}

local function ensure_type(x, ty, name)
	if type(x) ~= ty then
		error(("'%s' must be %s"):format(name, ty))
	end
	return x
end

local function ensure_bool(name)
	return function(x)
		return ensure_type(x, "boolean", name)
	end
end

local function ensure_string(name)
	return function(x)
		return ensure_type(x, "string", name)
	end
end

local function ensure_number(name)
	return function(x)
		return ensure_type(x, "number", name)
	end
end

local function ensure_encoding(x)
	if type(x) == "string" and util.normalize_encoding(x) then
		return x
	end
	error(("%s is invalid encoding"):format(tostring(x)))
end

-- string | [string, string] の配列
local function ensure_path_list(name)
	return function(x)
		if type(x) ~= "table" then
			error(("'%s' must be array of two string tuple"):format(name))
		end
		for _, v in ipairs(x) do
			local ok = type(v) == "string"
				or (type(v) == "table" and type(v[1]) == "string" and type(v[2]) == "string")
			if not ok then
				error(("'%s' must be array of two string tuple"):format(name))
			end
		end
		return x
	end
end

local validators = {
	acceptIllegalResult = ensure_bool("acceptIllegalResult"),
	completion = function(x)
		ensure_type(x, "table", "completion")
		local merged = vim.tbl_extend("force", vim.deepcopy(M.default_completion), x)
		ensure_type(merged.enabled, "boolean", "completion.enabled")
		ensure_type(merged.insertOnSelect, "boolean", "completion.insertOnSelect")
		ensure_type(merged.deferOkuri, "boolean", "completion.deferOkuri")
		return merged
	end,
	completionRankFile = ensure_string("completionRankFile"),
	databasePath = ensure_string("databasePath"),
	debug = ensure_bool("debug"),
	eggLikeNewline = ensure_bool("eggLikeNewline"),
	globalDictionaries = ensure_path_list("globalDictionaries"),
	globalKanaTableFiles = ensure_path_list("globalKanaTableFiles"),
	immediatelyCancel = ensure_bool("immediatelyCancel"),
	immediatelyDictionaryRW = ensure_bool("immediatelyDictionaryRW"),
	immediatelyOkuriConvert = ensure_bool("immediatelyOkuriConvert"),
	indicator = function(x)
		ensure_type(x, "table", "indicator")
		-- 部分指定をデフォルトへマージする
		local merged = vim.tbl_extend("force", vim.deepcopy(default_indicator), x)
		for _, key in ipairs({ "enabled", "alwaysShown", "useDefaultHighlight" }) do
			ensure_type(merged[key], "boolean", "indicator." .. key)
		end
		for _, key in ipairs({ "fadeOutMs", "col" }) do
			ensure_type(merged[key], "number", "indicator." .. key)
		end
		for _, name in ipairs({ "eiji", "hira", "kata", "hankata", "zenkaku", "abbrev" }) do
			ensure_type(merged[name .. "Text"], "string", "indicator." .. name .. "Text")
			ensure_type(merged[name .. "HlName"], "string", "indicator." .. name .. "HlName")
		end
		ensure_type(merged.ignoreFt, "table", "indicator.ignoreFt")
		return merged
	end,
	kanaTable = function(x)
		local name = ensure_type(x, "string", "kanaTable")
		local ok = pcall(require("skkelua.kana").get_kana_table, name)
		if not ok then
			error("can't use undefined kanaTable: " .. name)
		end
		return name
	end,
	keepMode = ensure_bool("keepMode"),
	keepState = ensure_bool("keepState"),
	mappedKeys = function(x)
		ensure_type(x, "table", "mappedKeys")
		for _, v in ipairs(x) do
			if type(v) ~= "string" then
				error("'mappedKeys' must be array of string")
			end
		end
		return x
	end,
	lowercaseMap = function(x)
		ensure_type(x, "table", "lowercaseMap")
		for k, v in pairs(x) do
			if type(k) ~= "string" or type(v) ~= "string" then
				error("'lowercaseMap' must be record of string")
			end
		end
		return x
	end,
	markerHenkan = ensure_string("markerHenkan"),
	markerHenkanSelect = ensure_string("markerHenkanSelect"),
	registerConvertResult = ensure_bool("registerConvertResult"),
	selectCandidateKeys = function(x)
		local keys = ensure_type(x, "string", "selectCandidateKeys")
		if #keys ~= 7 then
			error("selectCandidateKeys.length !== 7")
		end
		return keys
	end,
	setUndoPoint = ensure_bool("setUndoPoint"),
	showCandidatesCount = ensure_number("showCandidatesCount"),
	skkServerHost = ensure_string("skkServerHost"),
	skkServerPort = ensure_number("skkServerPort"),
	skkServerReqEnc = ensure_encoding,
	skkServerResEnc = ensure_encoding,
	sources = function(x)
		ensure_type(x, "table", "sources")
		for _, v in ipairs(x) do
			if type(v) ~= "string" then
				error("'sources' must be array of string")
			end
		end
		return x
	end,
	useGoogleJapaneseInput = function()
		error('`useGoogleJapaneseInput` is removed. Please use `sources` with "google_japanese_input"')
	end,
	useSkkServer = function()
		error('`useSkkServer` is removed. Please use `sources` with "skk_server"')
	end,
	userDictionary = ensure_string("userDictionary"),
}

local function normalize()
	local c = M.config
	local dicts = {}
	for _, cfg in ipairs(c.globalDictionaries) do
		if type(cfg) == "string" then
			dicts[#dicts + 1] = { util.home_expand(cfg), "" }
		else
			dicts[#dicts + 1] = { util.home_expand(cfg[1]), cfg[2] }
		end
	end
	c.globalDictionaries = dicts

	local tables = {}
	for _, cfg in ipairs(c.globalKanaTableFiles) do
		if type(cfg) == "string" then
			tables[#tables + 1] = util.home_expand(cfg)
		else
			tables[#tables + 1] = { util.home_expand(cfg[1]), cfg[2] }
		end
	end
	c.globalKanaTableFiles = tables

	c.userDictionary = util.home_expand(c.userDictionary)
	c.completionRankFile = util.home_expand(c.completionRankFile)
	c.databasePath = util.home_expand(c.databasePath)
end

--- 設定を検証して反映する (setConfig 相当)
---@param new_config table<string, any>
function M.set_config(new_config)
	if M.config.debug then
		vim.print("skkelua: new config")
		vim.print(new_config)
	end
	for k, v in pairs(new_config) do
		local validator = validators[k]
		if not validator then
			error(("Illegal option detected: unknown option: %s"):format(k))
		end
		local ok, result_or_err = pcall(validator, v)
		if not ok then
			error(("Illegal option detected: %s"):format(result_or_err))
		end
		M.config[k] = result_or_err
	end
	normalize()

	require("skkelua.kana").load_kana_table_files(M.config.globalKanaTableFiles)

	-- indicator が起動済みなら新しい設定で表示を作り直す
	require("skkelua.indicator").refresh()
end

return M
