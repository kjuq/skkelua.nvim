-- ローカルの skkelua を普段の設定と切り離して試すための最小設定
--
-- 使い方:
--   nvim -u ~/codes/skkeleton-lua/skkelua/tests/minimal_init.lua
--
-- insert モードで <C-j> でオン・オフ。ステータスラインに現在のモードが出る。
-- ユーザー辞書はテスト用に /tmp に書くので、普段の辞書は汚れない。

local this_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(this_file))
vim.opt.runtimepath:prepend(root)

-- 辞書: skk-dev/dict (lazy.nvim で導入済みのもの) があれば使う
local dicts = {}
for _, name in ipairs({ "SKK-JISYO.L", "SKK-JISYO.jinmei" }) do
	local path = vim.fn.expand("~/.local/share/nvim/lazy/dict/" .. name)
	if vim.uv.fs_stat(path) then
		dicts[#dicts + 1] = path
	end
end

require("skkelua").config({
	globalDictionaries = dicts,
	userDictionary = "/tmp/skkelua_test_jisyo",
})

vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkelua-toggle)")

-- モード表示
vim.opt.laststatus = 2
local function update_statusline()
	local mode = require("skkelua").mode()
	local label = mode ~= "" and ("skk:" .. mode) or "skk:off"
	vim.o.statusline = "%f %m%=" .. label .. " "
end
update_statusline()
vim.api.nvim_create_autocmd("User", {
	pattern = "skkelua-mode-changed",
	callback = update_statusline,
})

-- 起動後に辞書を事前ロードして初回有効化を速くする (任意)
vim.api.nvim_create_autocmd("UIEnter", {
	once = true,
	callback = function()
		local start = vim.uv.hrtime()
		require("skkelua").initialize()
		vim.notify(("skkelua: dictionaries loaded in %.0fms"):format((vim.uv.hrtime() - start) / 1e6))
	end,
})
