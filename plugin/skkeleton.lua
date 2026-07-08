-- skkeleton プラグインエントリ (plugin/skkeleton.vim に相当)

if vim.g.loaded_skkeleton then
	return
end
vim.g.loaded_skkeleton = true

-- 参照用の写し
vim.g["skkeleton#enabled"] = false
vim.g["skkeleton#mode"] = ""
vim.g["skkeleton#state"] = { phase = "" }

-- g:skkeleton#mapped_keys の初期化 (ユーザーが事前に設定した分は保持する)
local user_keys = vim.g["skkeleton#mapped_keys"] or {}
local keys = vim.list_extend(user_keys, require("skkeleton").get_default_mapped_keys())
vim.g["skkeleton#mapped_keys"] = keys

-- User autocmd のダミー定義 (doautocmd の警告防止)
local group = vim.api.nvim_create_augroup("skkeleton-internal", { clear = true })
vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "skkeleton*",
	command = ":",
})

for _, mode in ipairs({ { "i", "c" }, { "t" } }) do
	for _, action in ipairs({ "enable", "disable", "toggle" }) do
		vim.keymap.set(
			mode,
			("<Plug>(skkeleton-%s)"):format(action),
			("<Cmd>lua require('skkeleton').handle(%q, {})<CR>"):format(action)
		)
	end
end

-- Cause unexpected behavior when lmap is empty
-- (enable action was failed)
-- so makes dummy mapping
vim.keymap.set("l", "<Plug>(skkeleton-dummy)", ":")
