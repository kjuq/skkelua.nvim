-- 実バッファ + キーマッピング経由の統合テスト
-- (denops 版では test({mode: "nvim"}) で行われていた類のテスト)

local t = require("tests.helper")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "tx")
end

local function with_buffer(fn)
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	local ok, err = pcall(fn)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
end

t.test("henkan pipeline on real buffer", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")

	with_buffer(function()
		-- 変換して <CR> で確定
		feed("iJKanji \r")
		t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("okuriari henkan on real buffer", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okuriari", "おくr", "送")

	with_buffer(function()
		feed("iJOkuRi\r")
		t.assert_equals({ "送り", "" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("katakana mode on real buffer", function()
	with_buffer(function()
		feed("iJqkatakana")
		t.assert_equals("カタカナ", vim.fn.getline(1))
	end)
end)

t.test("disable with l key", function()
	with_buffer(function()
		feed("iJnihongolenglish")
		t.assert_equals("にほんごenglish", vim.fn.getline(1))
		t.assert_equals(false, require("skkelua").is_enabled())
	end)
end)

t.test("zenkaku mode", function()
	with_buffer(function()
		feed("iJLabc")
		t.assert_equals("ａｂｃ", vim.fn.getline(1))
	end)
end)

t.test("escape from henkan state", function()
	with_buffer(function()
		-- <Esc> で変換状態を破棄して insert を抜ける
		feed("iJKanji")
		feed("\27")
		t.assert_equals("n", vim.fn.mode())
	end)
end)

t.test("toggle mapping", function()
	with_buffer(function()
		vim.cmd("imap <buffer> <C-t> <Plug>(skkelua-toggle)")
		feed("i\20aiueo")
		t.assert_equals("あいうえお", vim.fn.getline(1))
	end)
end)

t.test("mode api and autocmds", function()
	with_buffer(function()
		local skkelua = require("skkelua")
		local enable_fired = false
		local autocmd_id = vim.api.nvim_create_autocmd("User", {
			pattern = "skkelua-enable-post",
			callback = function()
				enable_fired = true
			end,
		})
		feed("iJ")
		t.assert_equals("hira", skkelua.mode())
		t.assert_equals(true, enable_fired)
		t.assert_equals(true, skkelua.is_enabled())
		vim.api.nvim_del_autocmd(autocmd_id)
	end)
end)

t.test("buffer local maps are restored after disable", function()
	with_buffer(function()
		vim.cmd("inoremap <buffer> a XXX")
		feed("iJnihongo")
		t.assert_equals("にほんご", vim.fn.getline(1))
		-- disable で元のマッピングに戻る
		require("skkelua").disable_impl()
		-- Note: feedkeys の 'x' フラグは実行後 insert モードを抜けるため
		--       append で入り直す
		feed("aa")
		t.assert_equals("にほんごXXX", vim.fn.getline(1))
	end)
end)
