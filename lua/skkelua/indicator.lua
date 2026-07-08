-- モードインジケータ
-- skkeleton_indicator.nvim (Copyright (c) 2021 Yasushi Jinnouchi, zlib license)
-- を skkelua 向けに再構成して内蔵したもの

local M = {}

local MODE_NAMES = { "eiji", "hira", "kata", "hankata", "zenkaku", "abbrev" }

-- デフォルトカラースキーム用のハイライト定義
local default_hl = {
	dark = {
		eiji = { fg = "NvimLightBlue", bg = "NvimDarkGrey2", ctermfg = "blue", ctermbg = "black", bold = true },
		hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "black", ctermbg = "green", bold = true },
		kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "black", ctermbg = "yellow", bold = true },
		hankata = {
			fg = "NvimDarkGrey2",
			bg = "NvimLightMagenta",
			ctermfg = "black",
			ctermbg = "magenta",
			bold = true,
		},
		zenkaku = { fg = "NvimLightGrey2", bg = "NvimDarkCyan", ctermfg = "black", ctermbg = "cyan", bold = true },
		abbrev = { fg = "NvimLightGrey2", bg = "NvimDarkRed", ctermfg = "white", ctermbg = "red", bold = true },
	},
	light = {
		eiji = { fg = "NvimDarkBlue", bg = "NvimLightGrey2", ctermfg = "blue", ctermbg = "white", bold = true },
		hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "white", ctermbg = "green", bold = true },
		kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "white", ctermbg = "yellow", bold = true },
		hankata = {
			fg = "NvimDarkGrey2",
			bg = "NvimLightMagenta",
			ctermfg = "white",
			ctermbg = "magenta",
			bold = true,
		},
		zenkaku = { fg = "NvimDarkGrey2", bg = "NvimLightBlue", ctermfg = "black", ctermbg = "blue", bold = true },
		abbrev = { fg = "NvimDarkGrey2", bg = "NvimLightRed", ctermfg = "black", ctermbg = "red", bold = true },
	},
}

local function indicator_config()
	return require("skkelua.config").config.indicator
end

---@class skkelua.IndicatorMode
---@field name string
---@field text string
---@field hl_name string
---@field width integer

--- 設定からモード定義 (テキスト・ハイライト) を構築する
---@return table<string, skkelua.IndicatorMode>
local function build_modes()
	local config = indicator_config()
	local modes = {}
	for _, name in ipairs(MODE_NAMES) do
		local hl_name = config[name .. "HlName"]
		local text = config[name .. "Text"]
		local hl = vim.api.nvim_get_hl(0, { name = hl_name })
		local is_default_colorscheme = not vim.g.colors_name
		if vim.tbl_isempty(hl) or (is_default_colorscheme and config.useDefaultHighlight) then
			hl = default_hl[vim.o.background][name]
		end
		vim.api.nvim_set_hl(0, hl_name, hl)
		modes[name] = {
			name = name,
			text = text,
			hl_name = hl_name,
			width = vim.fn.strdisplaywidth(text),
		}
	end
	return modes
end

--------------------------------------------------------------------
-- Indicator
--------------------------------------------------------------------

---@class skkelua.Indicator
---@field ns integer
---@field modes table<string, skkelua.IndicatorMode>
---@field timer uv.uv_timer_t
---@field winid integer[]
local Indicator = {}
Indicator.__index = Indicator

function Indicator.new()
	local self = setmetatable({
		ns = vim.api.nvim_create_namespace("skkelua-indicator"),
		modes = build_modes(),
		timer = assert(vim.uv.new_timer()),
		winid = {},
	}, Indicator)
	local group = vim.api.nvim_create_augroup("skkelua-indicator", { clear = true })
	local defs = {
		{ "InsertEnter", "*", self:method("open") },
		{ "InsertLeave", "*", self:method("close") },
		{ "CursorMovedI", "*", self:method("move") },
		{ "User", "skkelua-mode-changed", self:method("update", "mode-changed") },
		{ "User", "skkelua-disable-post", self:method("update", "disable-post") },
		{ "User", "skkelua-enable-post", self:method("update", "enable-post") },
		{ "OptionSet", "background", self:method("refresh") },
	}
	for _, def in ipairs(defs) do
		vim.api.nvim_create_autocmd(def[1], { group = group, pattern = def[2], callback = def[3] })
	end
	return self
end

---@param name string
---@param ... any
---@return fun(): nil
function Indicator:method(name, ...)
	local arg = { ... }
	return function()
		self[name](self, unpack(arg))
	end
end

--- 現在のモード定義を返す
---@return skkelua.IndicatorMode
function Indicator:detect()
	local name = require("skkelua").mode()
	if name == "" or not self.modes[name] then
		name = "eiji"
	end
	return self.modes[name]
end

---@return boolean
function Indicator:is_disabled()
	local config = indicator_config()
	if not config.alwaysShown and not require("skkelua").is_enabled() then
		return true
	end
	local buf = vim.api.nvim_get_current_buf()
	if vim.tbl_contains(config.ignoreFt, vim.bo[buf].filetype) then
		return true
	end
	if config.bufFilter and not config.bufFilter(buf) then
		return true
	end
	return false
end

---@param buf integer
---@param mode skkelua.IndicatorMode
function Indicator:set_text(buf, mode)
	local config = indicator_config()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { mode.text })
	vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
	vim.hl.range(buf, self.ns, mode.hl_name, { 0, 0 }, { 0, -1 })
	self.timer:stop()
	if config.fadeOutMs > 0 then
		self.timer:start(config.fadeOutMs, 0, self:method("close"))
	end
end

---@param mode skkelua.IndicatorMode
---@return any
function Indicator:border(mode)
	local border_opt = indicator_config().border
	if type(border_opt) == "function" then
		return border_opt({ mode = mode.name }) or { " " }
	end
	return border_opt
end

--- row のデフォルトは border の有無で変わる
---@return integer
function Indicator:row()
	local config = indicator_config()
	if config.row then
		return config.row
	end
	local border = config.border
	return (not border or border == "none" or border == "shadow") and 1 or 0
end

---@param winid integer
---@param mode skkelua.IndicatorMode
function Indicator:border_highlight(winid, mode)
	vim.wo[winid].winhighlight = "FloatBorder:" .. mode.hl_name
end

function Indicator:open()
	if self:is_opened() or self:is_disabled() or self:is_in_cmdwin() then
		return
	end
	local config = indicator_config()
	local mode = self:detect()
	local buf = vim.api.nvim_create_buf(false, true)
	self:set_text(buf, mode)
	local winid = vim.api.nvim_open_win(buf, false, {
		style = "minimal",
		relative = "cursor",
		row = self:row(),
		col = config.col,
		height = 1,
		width = mode.width,
		focusable = false,
		noautocmd = true,
		border = self:border(mode),
		zindex = config.zindex,
	})
	self:border_highlight(winid, mode)
	table.insert(self.winid, 1, winid)
end

---@param event string
function Indicator:update(event)
	vim.schedule(function()
		-- Note: InsertLeave 時にも mode-changed が発火するため、
		--       insert モードにいることを確認する
		if not vim.api.nvim_get_mode().mode:find("i") then
			return
		end

		if event == "disable-post" and not indicator_config().alwaysShown then
			self:close()
			return
		end

		if self:is_opened() then
			local winid = self.winid[1]
			local mode = self:detect()
			local buf = vim.api.nvim_win_get_buf(winid)
			self:set_text(buf, mode)
			pcall(vim.api.nvim_win_set_config, winid, { border = self:border(mode), width = mode.width })
			self:border_highlight(winid, mode)
		else
			self:open()
		end
	end)
end

function Indicator:move()
	if self:is_opened() and self.winid[1] then
		local mode = self:detect()
		-- Note: ウィンドウが既に消えていると失敗することがある
		local ok = pcall(vim.api.nvim_win_set_config, self.winid[1], {
			relative = "cursor",
			row = self:row(),
			col = indicator_config().col,
			width = mode.width,
		})
		if not ok then
			table.remove(self.winid, 1)
		end
	end
end

function Indicator:close()
	self.timer:stop()
	if not self:is_opened() then
		return
	end
	local winids = self.winid
	self.winid = {}
	for i = #winids, 1, -1 do
		local winid = winids[i]
		vim.schedule(function()
			local ok, buf = pcall(vim.api.nvim_win_get_buf, winid)
			if not ok then
				return
			end
			pcall(vim.api.nvim_win_close, winid, true)
			pcall(vim.api.nvim_buf_clear_namespace, buf, self.ns, 0, -1)
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end)
	end
end

---@return boolean
function Indicator:is_opened()
	return #self.winid > 0
end

---@return boolean
function Indicator:is_in_cmdwin()
	return vim.fn.getcmdwintype() ~= ""
end

function Indicator:refresh()
	self.modes = build_modes()
	self:update("mode-changed")
end

--------------------------------------------------------------------
-- モジュール API
--------------------------------------------------------------------

---@type skkelua.Indicator?
local instance = nil

--- インジケータを起動する (plugin/skkelua.lua の InsertEnter から呼ばれる)
function M.attach()
	if instance then
		return
	end
	if not indicator_config().enabled then
		return
	end
	instance = Indicator.new()
	instance:open()
end

--- 設定変更を表示へ反映する (未起動なら何もしない)
function M.refresh()
	if instance then
		instance:refresh()
	end
end

--- テスト用: インスタンスを破棄する
function M._reset_for_test()
	if instance then
		instance:close()
		pcall(vim.api.nvim_del_augroup_by_name, "skkelua-indicator")
		instance = nil
	end
end

--- テスト用: 現在のインスタンスを返す
function M._instance()
	return instance
end

return M
