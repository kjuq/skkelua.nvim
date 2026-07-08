-- 設定管理 (config.ts に相当)

local util = require("skkelua.util")

local M = {}

---@class skkelua.ConfigOptions
M.config = {
	acceptIllegalResult = false,
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
	kanaTable = "rom",
	keepMode = false,
	keepState = false,
	---@type table<string, string>
	lowercaseMap = {},
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
	userDictionary = "~/.skkeleton",
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
	completionRankFile = ensure_string("completionRankFile"),
	databasePath = ensure_string("databasePath"),
	debug = ensure_bool("debug"),
	eggLikeNewline = ensure_bool("eggLikeNewline"),
	globalDictionaries = ensure_path_list("globalDictionaries"),
	globalKanaTableFiles = ensure_path_list("globalKanaTableFiles"),
	immediatelyCancel = ensure_bool("immediatelyCancel"),
	immediatelyDictionaryRW = ensure_bool("immediatelyDictionaryRW"),
	immediatelyOkuriConvert = ensure_bool("immediatelyOkuriConvert"),
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
end

return M
