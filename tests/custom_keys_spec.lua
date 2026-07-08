-- 変換キーのカスタマイズ (denops 版の実運用設定パターンの再現)
--
-- 以下の denops 版設定に相当する操作が動くことを確認する:
--   call skkeleton#register_kanatable('rom', {' ': [' ', '']})
--   call skkeleton#register_keymap('input', '<C-n>', 'henkanFirst')
--   call skkeleton#register_keymap('henkan', '<C-n>', 'henkanForward')
--   call skkeleton#register_keymap('henkan', '<C-p>', 'henkanBackward')
--   call skkeleton#handle('handleKey', {'function': 'kakutei'})

local t = require("tests.helper")

--- キーを処理し、バッファへ送出されるはずの文字列 (result) を返す
local function handle_key(key)
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local vim_status = {
		mode = "",
		prevInput = store.get_context():to_string(),
		completeInfo = {},
		completeType = "",
	}
	local ret = skkelua._handle_request("handleKey", { key = { key } }, vim_status)
	return ret.result
end

local function setup_custom_keys()
	local skkelua = require("skkelua")
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")
	-- Space を変換キーではなく通常の空白入力にする
	skkelua.register_kanatable("rom", { [" "] = { " ", "" } })
	-- 代わりに <C-n>/<C-p> で変換を操作する
	skkelua.register_keymap("input", "<C-n>", "henkanFirst")
	skkelua.register_keymap("henkan", "<C-n>", "henkanForward")
	skkelua.register_keymap("henkan", "<C-p>", "henkanBackward")
	return skkelua
end

t.test("henkan key can be changed from Space to <C-n>", function()
	setup_custom_keys()
	local store = require("skkelua.store")
	store.init_context()

	-- ▽かんじ を組み立てて <C-n> で変換開始
	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		handle_key(k)
	end
	t.assert_equals("▽かんじ", store.get_context():to_string())
	handle_key("<c-n>")
	t.assert_equals("▼感じ", store.get_context():to_string())
	-- <C-n> で次候補、<C-p> で前候補
	handle_key("<c-n>")
	t.assert_equals("▼漢字", store.get_context():to_string())
	handle_key("<c-p>")
	t.assert_equals("▼感じ", store.get_context():to_string())
end)

t.test("Space inputs a plain space after remapping", function()
	setup_custom_keys()
	local store = require("skkelua.store")
	store.init_context()

	-- direct モードでは空白がそのまま入る (変換は始まらない)
	local out = handle_key("a") .. handle_key("<space>") .. handle_key("i")
	t.assert_equals("あ い", out)
	t.assert_equals("input", store.get_context().state.type)
end)

t.test("handle with function option (kakutei)", function()
	setup_custom_keys()
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	store.init_context()

	for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
		handle_key(k)
	end
	t.assert_equals("▽かんじ", store.get_context():to_string())
	-- skkeleton#handle('handleKey', {'function': 'kakutei'}) 相当
	local context = store.get_context()
	local ret = skkelua._handle_request("handleKey", { key = { "" }, ["function"] = "kakutei" }, {
		mode = "",
		prevInput = context:to_string(),
		completeInfo = {},
		completeType = "",
	})
	-- ▽かんじ (4 文字) を BS で消してから確定文字列を入れる
	t.assert_equals("\b\b\b\bかんじ", ret.result)
end)

t.test("mapped_keys can be extended (<C-n> works via buffer mapping)", function()
	setup_custom_keys()
	local store = require("skkelua.store")

	-- g:skkeleton#mapped_keys に <C-n> を足すと有効化時にマップされる
	local saved = vim.g["skkeleton#mapped_keys"]
	local keys = vim.deepcopy(saved or require("skkelua").get_default_mapped_keys())
	table.insert(keys, "<C-n>")
	vim.g["skkeleton#mapped_keys"] = keys

	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	local ok, err = pcall(function()
		vim.fn.feedkeys(
			vim.api.nvim_replace_termcodes("iJKanji<C-n>", true, true, true),
			"tx"
		)
		t.assert_equals("▼感じ", store.get_context():to_string())
	end)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	vim.g["skkeleton#mapped_keys"] = saved
	if not ok then
		error(err, 0)
	end
end)
