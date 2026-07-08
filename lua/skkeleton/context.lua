-- 変換コンテキスト (context.ts に相当)

local preedit = require("skkeleton.preedit")
local state_mod = require("skkeleton.state")

local M = {}

---@class skkeleton.CandidateResult
---@field type "okuriari"|"okurinasi"
---@field word string
---@field candidate string

---@class skkeleton.Context
---@field state skkeleton.State
---@field mode string g:skkeleton#mode の写し (modeChange から設定される)
---@field preEdit skkeleton.PreEdit
---@field vimMode string
---@field lastCandidate skkeleton.CandidateResult
local Context = {}
Context.__index = Context

function Context.new()
	local self = setmetatable({}, Context)
	self.state = state_mod.initialize_state({})
	self.mode = "hira"
	self.preEdit = preedit.PreEdit.new()
	self.vimMode = ""
	self.lastCandidate = {
		type = "okurinasi",
		word = "",
		candidate = "",
	}
	return self
end

---@param str string
function Context:kakutei(str)
	self.preEdit:do_kakutei(str)
end

---@param str string
function Context:kakutei_with_undo_point(str)
	local config = require("skkeleton.config").config
	if config.setUndoPoint and self.vimMode == "i" then
		-- <C-g>u で undo point を切る
		str = str .. "\7u"
	end
	self.preEdit:do_kakutei(str)
end

---@return string
function Context:to_string()
	return state_mod.to_string(self.state)
end

M.Context = Context

--- store.lua から使うためのコンストラクタ
function M.new()
	return Context.new()
end

return M
