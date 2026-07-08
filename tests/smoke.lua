-- 全モジュールがロードできるかのスモークテスト
-- 使い方: nvim --clean --headless -l tests/smoke.lua

local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.runtimepath:prepend(root)

local modules = {
	"skkeleton.util",
	"skkeleton.notation",
	"skkeleton.kana.rom_hira",
	"skkeleton.kana.rom_zen",
	"skkeleton.kana.hira_kata",
	"skkeleton.kana.hira_hankata",
	"skkeleton.config",
	"skkeleton.store",
	"skkeleton.kana",
	"skkeleton.candidate",
	"skkeleton.okuri",
	"skkeleton.preedit",
	"skkeleton.state",
	"skkeleton.context",
	"skkeleton.mode",
	"skkeleton.function",
	"skkeleton.function.input",
	"skkeleton.function.common",
	"skkeleton.function.henkan",
	"skkeleton.function.mode",
	"skkeleton.function.disable",
	"skkeleton.function.dictionary",
	"skkeleton.keymap",
	"skkeleton.dictionary",
	"skkeleton.sources.skk_dictionary",
	"skkeleton.sources.user_dictionary",
	"skkeleton.sources.skk_server",
	"skkeleton.sources.google_japanese_input",
	"skkeleton.popup",
	"skkeleton.map",
	"skkeleton.option",
	"skkeleton",
}

local failed = 0
for _, mod in ipairs(modules) do
	local ok, err = pcall(require, mod)
	if ok then
		print(("OK   %s"):format(mod))
	else
		failed = failed + 1
		print(("FAIL %s: %s"):format(mod, err))
	end
end

-- 簡単な動作確認
local function try(label, fn)
	local ok, err = pcall(fn)
	if ok then
		print(("OK   %s"):format(label))
	else
		failed = failed + 1
		print(("FAIL %s: %s"):format(label, err))
	end
end

try("get_kana_table", function()
	local t = require("skkeleton.kana").get_kana_table("rom")
	assert(#t > 200, "rom table too small")
end)

try("kana input roundtrip", function()
	local context = require("skkeleton.context").new()
	local input = require("skkeleton.function.input")
	input.kana_input(context, "k")
	input.kana_input(context, "a")
	assert(context.preEdit:output("") == "か", "expected か")
end)

try("hira_to_kata", function()
	assert(require("skkeleton.kana.hira_kata").hira_to_kata("あいう") == "アイウ")
end)

try("char_sub", function()
	local util = require("skkeleton.util")
	assert(util.char_sub("あいう", 1, -2) == "あい")
	assert(util.char_sub("あいう", -1) == "う")
	assert(util.char_sub("abc", 2) == "bc")
end)

if failed > 0 then
	print(("%d failures"):format(failed))
	vim.cmd.cquit()
else
	print("all passed")
	vim.cmd.quitall()
end
