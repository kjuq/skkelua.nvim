-- skkelua プラグインエントリ (skkeleton の plugin/skkeleton.vim に相当)

if vim.g.loaded_skkelua then
	return
end
vim.g.loaded_skkelua = true

-- 参照用の写し
-- Note: 変数名は skkeleton エコシステム (skkeleton_indicator.nvim など) との
--       互換のため skkeleton# を使う
vim.g["skkeleton#enabled"] = false
vim.g["skkeleton#mode"] = ""
vim.g["skkeleton#state"] = { phase = "" }

-- g:skkeleton#mapped_keys の初期化 (ユーザーが事前に設定した分は保持する)
local user_keys = vim.g["skkeleton#mapped_keys"] or {}
local keys = vim.list_extend(user_keys, require("skkelua").get_default_mapped_keys())
vim.g["skkeleton#mapped_keys"] = keys

-- User autocmd のダミー定義 (doautocmd の警告防止)
local group = vim.api.nvim_create_augroup("skkelua-internal", { clear = true })
vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "skkeleton*",
	command = ":",
})

-- <Plug>(skkelua-*) が正式名。<Plug>(skkeleton-*) は denops 版からの
-- 移行用の互換エイリアス
for _, mode in ipairs({ { "i", "c" }, { "t" } }) do
	for _, action in ipairs({ "enable", "disable", "toggle" }) do
		local rhs = ("<Cmd>lua require('skkelua').handle(%q, {})<CR>"):format(action)
		vim.keymap.set(mode, ("<Plug>(skkelua-%s)"):format(action), rhs)
		vim.keymap.set(mode, ("<Plug>(skkeleton-%s)"):format(action), rhs)
	end
end

-- Cause unexpected behavior when lmap is empty
-- (enable action was failed)
-- so makes dummy mapping
vim.keymap.set("l", "<Plug>(skkelua-dummy)", ":")
