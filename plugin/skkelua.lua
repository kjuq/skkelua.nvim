-- skkelua プラグインエントリ

if vim.g.loaded_skkelua then
	return
end
vim.g.loaded_skkelua = true

for _, mode in ipairs({ { "i", "c" }, { "t" } }) do
	for _, action in ipairs({ "enable", "disable", "toggle" }) do
		vim.keymap.set(
			mode,
			("<Plug>(skkelua-%s)"):format(action),
			("<Cmd>lua require('skkelua').handle(%q, {})<CR>"):format(action)
		)
	end
end

-- Cause unexpected behavior when lmap is empty
-- (enable action was failed)
-- so makes dummy mapping
vim.keymap.set("l", "<Plug>(skkelua-dummy)", ":")
