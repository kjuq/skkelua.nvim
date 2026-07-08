-- 入力状態の定義と文字列化 (state.ts に相当)

local M = {}

---@alias skkeleton.InputMode "direct"|"okurinasi"|"okuriari"
---@alias skkeleton.AffixType "prefix"|"suffix"

---@class skkeleton.InputState
---@field type "input"
---@field mode skkeleton.InputMode
---@field affix? skkeleton.AffixType
---@field directInput boolean trueだと大文字が打たれた時に変換ポイントを切らなくなる (abbrevに必要)
---@field table skkeleton.KanaTable
---@field converter? fun(input: string): string
---@field feed string
---@field henkanFeed string
---@field okuriFeed string
---@field previousFeed boolean かなフィードが変換ポイントの前にあるかどうか (「察し」などを変換するのに必要)

---@class skkeleton.HenkanState: skkeleton.InputState
---@field type "henkan"
---@field mode "okurinasi"|"okuriari"
---@field word string
---@field candidates string[]
---@field candidateIndex integer 0-origin (TS 版と揃える)

---@alias skkeleton.State skkeleton.InputState|skkeleton.HenkanState|{ type: "escape" }

-- initializeState で必ず上書きされるフィールド
-- (converter を nil で確実に消すため、キーの列挙を持つ)
local DEFAULT_FIELDS = {
	"type",
	"mode",
	"directInput",
	"table",
	"converter",
	"feed",
	"henkanFeed",
	"okuriFeed",
	"previousFeed",
}

---@return skkeleton.InputState
local function default_input_state()
	return {
		type = "input",
		mode = "direct",
		directInput = false,
		table = require("skkeleton.kana").get_kana_table(),
		converter = nil,
		feed = "",
		henkanFeed = "",
		okuriFeed = "",
		previousFeed = false,
	}
end

--- state を初期状態に戻す (オブジェクト同一性は保つ)
--- ignore に指定したフィールドは保持される
---@param state table
---@param ignore? string[]
---@return skkeleton.InputState
function M.initialize_state(state, ignore)
	local ignored = {}
	for _, key in ipairs(ignore or {}) do
		ignored[key] = state[key]
	end
	local def = default_input_state()
	for _, key in ipairs(DEFAULT_FIELDS) do
		state[key] = def[key]
	end
	for key, value in pairs(ignored) do
		state[key] = value
	end
	return state
end

---@param state skkeleton.InputState
---@return string
local function input_state_to_string(state)
	local config = require("skkeleton.config").config
	local ret = ""
	if state.mode ~= "direct" then
		ret = config.markerHenkan .. state.henkanFeed
	end
	if state.mode == "okuriari" then
		if state.previousFeed then
			return ret .. state.feed .. "*"
		else
			ret = ret .. "*" .. state.okuriFeed
		end
	end
	if state.converter then
		ret = state.converter(ret)
	end
	return ret .. state.feed
end

---@param state skkeleton.HenkanState
---@return string
function M.henkan_state_to_string(state)
	local config = require("skkeleton.config").config
	local candidate = require("skkeleton.candidate").modify_candidate(
		state.candidates[state.candidateIndex + 1],
		state.affix
	) or "error"
	local okuri_str = state.converter and state.converter(state.okuriFeed) or state.okuriFeed
	return config.markerHenkanSelect .. candidate .. okuri_str
end

---@param state skkeleton.State
---@return string
function M.to_string(state)
	if state.type == "input" then
		return input_state_to_string(state)
	elseif state.type == "henkan" then
		return M.henkan_state_to_string(state)
	elseif state.type == "escape" then
		return "\27"
	else
		return ""
	end
end

return M
