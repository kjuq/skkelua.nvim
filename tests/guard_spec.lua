-- guard.lua (未マップ特殊キーの破棄ゲート) の判定ロジック

local t = require("tests.helper")

local function termcode(notation)
	return vim.api.nvim_replace_termcodes(notation, true, true, true)
end

t.test("physical special keys are classified for discard", function()
	local guard = require("skkelua.guard")

	-- KS_MODIFIER: 修飾キーの組み合わせ全般
	t.assert_true(guard._is_physical_special(termcode("<C-.>")), "<C-.>")
	t.assert_true(guard._is_physical_special(termcode("<S-CR>")), "<S-CR>")
	t.assert_true(guard._is_physical_special(termcode("<M-x>")), "<M-x>")
	-- termcap 系: ナビゲーション・ファンクションキー
	t.assert_true(guard._is_physical_special(termcode("<Left>")), "<Left>")
	t.assert_true(guard._is_physical_special(termcode("<Del>")), "<Del>")
	t.assert_true(guard._is_physical_special(termcode("<F5>")), "<F5>")
	-- KS_EXTRA のうち専用コードを持つ物理キー (列挙分)
	t.assert_true(guard._is_physical_special(termcode("<S-Up>")), "<S-Up>")
	t.assert_true(guard._is_physical_special(termcode("<C-Left>")), "<C-Left>")
	t.assert_true(guard._is_physical_special(termcode("<S-F5>")), "<S-F5>")
end)

t.test("hostile control bytes are classified for discard", function()
	local guard = require("skkelua.guard")

	-- pre-edit を壊す単バイト制御キー
	t.assert_true(guard._is_hostile_control(termcode("<C-r>")), "<C-r>")
	t.assert_true(guard._is_hostile_control(termcode("<C-k>")), "<C-k>")
	t.assert_true(guard._is_hostile_control(termcode("<C-v>")), "<C-v>")
	t.assert_true(guard._is_hostile_control(termcode("<C-a>")), "<C-a>")
	t.assert_true(guard._is_hostile_control("\127"), "DEL")
	-- skkelua 自身の出力に現れる制御バイトは対象外
	t.assert_true(not guard._is_hostile_control("\7"), "<C-g>u undo break")
	t.assert_true(not guard._is_hostile_control("\b"), "BS output")
	t.assert_true(not guard._is_hostile_control("\r"), "<CR>")
	t.assert_true(not guard._is_hostile_control(termcode("<Esc>")), "<Esc>")
	-- 通常の文字は対象外
	t.assert_true(not guard._is_hostile_control("a"), "ascii")
	t.assert_true(not guard._is_hostile_control("あ"), "kana")
end)

t.test("own output and internal pseudo keys are never discarded", function()
	local guard = require("skkelua.guard")

	-- skkelua 自身の feedkeys 出力に現れるバイト列
	t.assert_true(not guard._is_physical_special("あ"), "kana output")
	t.assert_true(not guard._is_physical_special("\b"), "BS output")
	t.assert_true(not guard._is_physical_special("\7"), "<C-g>u undo break")
	-- KS_SPECIAL: 全角スペースなど 0x80 バイトを含む本文のエスケープ形
	t.assert_true(not guard._is_physical_special("\128\254X"), "escaped K_SPECIAL")
	-- KS_EXTRA の内部擬似キー
	t.assert_true(not guard._is_physical_special(termcode("<Cmd>")), "<Cmd>")
	t.assert_true(not guard._is_physical_special(termcode("<Ignore>")), "<Ignore>")
end)
