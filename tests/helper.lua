-- 簡易テストハーネス

local M = {}

---@type { name: string, fn: fun() }[]
M.tests = {}

--- テストを登録する
---@param name string
---@param fn fun()
function M.test(name, fn)
	M.tests[#M.tests + 1] = { name = name, fn = fn }
end

--- deep 比較の assert (expected, actual の順は TS 版に合わせる)
function M.assert_equals(expected, actual, msg)
	if not vim.deep_equal(expected, actual) then
		error(
			("%sexpected: %s\nactual:   %s"):format(
				msg and (msg .. "\n") or "",
				vim.inspect(expected),
				vim.inspect(actual)
			),
			2
		)
	end
end

function M.assert_true(v, msg)
	if not v then
		error(("%sexpected truthy, got %s"):format(msg and (msg .. "\n") or "", vim.inspect(v)), 2)
	end
end

--- エラーが発生することを確認する
function M.assert_error(fn, msg)
	local ok = pcall(fn)
	if ok then
		error(("%sexpected error but succeeded"):format(msg and (msg .. "\n") or ""), 2)
	end
end

local default_config = nil

--- 各テストの前に skkeleton の内部状態をリセットする
function M.reset()
	local config_mod = require("skkeleton.config")
	if not default_config then
		default_config = vim.deepcopy(config_mod.config)
	end
	for k in pairs(config_mod.config) do
		config_mod.config[k] = nil
	end
	for k, v in pairs(vim.deepcopy(default_config)) do
		config_mod.config[k] = v
	end
	require("skkeleton.kana")._reset()
	require("skkeleton")._reset_for_test()
	require("skkeleton.store").variables.lastMode = "hira"
	vim.g["skkeleton#enabled"] = false
	vim.g["skkeleton#mode"] = ""
	-- TS 版テストハーネスの dispatcher.initialize(true) に相当:
	-- 実際のユーザー辞書を読まないよう設定を切り離した上で初期化まで済ませる
	-- (init() が library initializer を再設定するため、テスト中の register が
	--  init() のタイミングで破棄されないようにする)
	M.clean_dictionary_config()
	require("skkeleton").initialize()
end

--- ユーザー辞書を切り離す (グローバル設定汚染防止)
function M.clean_dictionary_config()
	local config = require("skkeleton.config").config
	config.globalDictionaries = {}
	config.userDictionary = ""
	config.completionRankFile = ""
end

--- テストデータのパスを返す
---@param name string
---@return string
function M.testdata(name)
	local dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
	return vim.fs.joinpath(vim.fn.fnamemodify(dir, ":p"), "testdata", name)
end

--- 一時ファイルパスを返す
function M.tempname()
	return vim.fn.tempname()
end

--- function/testutil.ts の dispatch 相当
---@param context skkeleton.Context
---@param keys string
function M.dispatch(context, keys)
	local util = require("skkeleton.util")
	local input = require("skkeleton.function.input")
	local henkan = require("skkeleton.function.henkan")
	local common = require("skkeleton.function.common")
	for _, key in ipairs(util.chars(keys)) do
		if context.state.type == "input" then
			if key == " " then
				henkan.henkan_first(context, key)
			elseif key == ";" then
				input.henkan_point(context)
			elseif key == "\n" then
				common.newline(context)
			else
				input.kana_input(context, key)
			end
		elseif context.state.type == "henkan" then
			if key == " " then
				henkan.henkan_forward(context)
			elseif key == "x" then
				henkan.henkan_backward(context)
			elseif key == "\n" then
				common.newline(context)
			end
		end
	end
end

--- 登録されたテストを全て実行する
---@return integer 失敗数
function M.run()
	local passed, failed = 0, 0
	for _, t in ipairs(M.tests) do
		M.reset()
		local ok, err = pcall(t.fn)
		if ok then
			passed = passed + 1
			print(("  ok   %s"):format(t.name))
		else
			failed = failed + 1
			print(("  FAIL %s\n       %s"):format(t.name, tostring(err):gsub("\n", "\n       ")))
		end
	end
	M.tests = {}
	return failed
end

return M
