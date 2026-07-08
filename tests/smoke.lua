-- 全モジュールがロードできるかのスモークテスト
-- 使い方: nvim --clean --headless -l tests/smoke.lua

local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.runtimepath:prepend(root)

local modules = {
	"skkelua.util",
	"skkelua.notation",
	"skkelua.kana.rom_hira",
	"skkelua.kana.rom_zen",
	"skkelua.kana.hira_kata",
	"skkelua.kana.hira_hankata",
	"skkelua.config",
	"skkelua.store",
	"skkelua.kana",
	"skkelua.candidate",
	"skkelua.okuri",
	"skkelua.preedit",
	"skkelua.state",
	"skkelua.context",
	"skkelua.mode",
	"skkelua.function",
	"skkelua.function.input",
	"skkelua.function.common",
	"skkelua.function.henkan",
	"skkelua.function.mode",
	"skkelua.function.disable",
	"skkelua.function.dictionary",
	"skkelua.keymap",
	"skkelua.dictionary",
	"skkelua.sources.skk_dictionary",
	"skkelua.sources.user_dictionary",
	"skkelua.sources.skk_server",
	"skkelua.sources.google_japanese_input",
	"skkelua.popup",
	"skkelua.map",
	"skkelua.option",
	"skkelua",
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
	local t = require("skkelua.kana").get_kana_table("rom")
	assert(#t > 200, "rom table too small")
end)

try("kana input roundtrip", function()
	local context = require("skkelua.context").new()
	local input = require("skkelua.function.input")
	input.kana_input(context, "k")
	input.kana_input(context, "a")
	assert(context.preEdit:output("") == "か", "expected か")
end)

try("hira_to_kata", function()
	assert(require("skkelua.kana.hira_kata").hira_to_kata("あいう") == "アイウ")
end)

try("char_sub", function()
	local util = require("skkelua.util")
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
