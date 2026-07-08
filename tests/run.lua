-- テストランナー
-- 使い方: nvim --clean --headless -l tests/run.lua [spec名...]

local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local tests_dir = vim.fs.dirname(script)
local root = vim.fs.dirname(tests_dir)
vim.opt.runtimepath:prepend(root)
package.path = ("%s/?.lua;%s"):format(root, package.path)

-- -l 起動では plugin/ が自動ロードされないため明示的にロードする
vim.cmd("runtime! plugin/skkeleton.lua")

local specs = {}
for name in vim.fs.dir(tests_dir) do
	local spec = name:match("^(.*_spec)%.lua$")
	if spec then
		specs[#specs + 1] = spec
	end
end
table.sort(specs)

-- 引数でフィルタ
local args = _G.arg or {}
if #args > 0 then
	local filtered = {}
	for _, spec in ipairs(specs) do
		for _, a in ipairs(args) do
			if spec:find(a, 1, true) then
				filtered[#filtered + 1] = spec
				break
			end
		end
	end
	specs = filtered
end

local helper = require("tests.helper")
local total_failed = 0

for _, spec in ipairs(specs) do
	print(spec)
	require("tests." .. spec)
	total_failed = total_failed + helper.run()
end

if total_failed > 0 then
	print(("\n%d test(s) failed"):format(total_failed))
	vim.cmd.cquit()
else
	print("\nall tests passed")
	vim.cmd.quitall()
end
