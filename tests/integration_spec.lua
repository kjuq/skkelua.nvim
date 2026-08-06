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

-- 未マップの特殊キー (<C-.> や <S-CR> など全列挙できない組み合わせ) は
-- guard.lua が pre-edit 中だけ破棄する。個別にマップして守る方式は
-- やめたため、以前 <CR> 相当にマップしていた <S-CR> もここに含まれる
for _, key in ipairs({ "<C-.>", "<S-CR>", "<Left>" }) do
	t.test(("unmapped %s is discarded during pre-edit"):format(key), function()
		with_buffer(function()
			-- 以前は Neovim デフォルト動作 (文字挿入やカーソル移動) が走って
			-- pre-edit が壊れ、▽ マーカーがゴミとして残っていた
			feed("iJKanji" .. key)
			t.assert_equals({ "▽かんじ" }, vim.fn.getline(1, "$"))
		end)
	end)

	t.test(("henkan continues after unmapped %s"):format(key), function()
		local lib = require("skkelua.store").get_library()
		lib:register_henkan_result("okurinasi", "かんじ", "漢字")

		with_buffer(function()
			-- 押しても何も起きず、そのまま変換・確定を続行できる
			feed("iJKanji" .. key .. " <CR>")
			t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
		end)
	end)
end

t.test("hostile control keys are discarded during pre-edit", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")

	with_buffer(function()
		-- <C-r> によるレジスタ貼り付けは破棄され、続く a は通常のかな入力になる
		vim.fn.setreg("a", "REG")
		feed("iJKanji<C-r>a")
		t.assert_equals({ "▽かんじあ" }, vim.fn.getline(1, "$"))
	end)

	with_buffer(function()
		-- <C-v> (リテラル入力) も破棄され、そのまま変換を続行できる
		feed("iJKanji<C-v> <CR>")
		t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
	end)

	with_buffer(function()
		-- <C-k> (digraph 入力) も破棄され、そのまま変換を続行できる
		feed("iJKanji<C-k> <CR>")
		t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("<C-n> still navigates pum during pre-edit", function()
	with_buffer(function()
		vim.opt_local.completeopt = "menuone,noselect"
		vim.cmd("inoremap <buffer> <C-t> <Cmd>call complete(col('.'), ['候補一', '候補二'])<CR>")
		local selected
		vim.keymap.set("i", "<C-b>", function()
			selected = vim.fn.complete_info({ "selected" }).selected
		end, { buffer = true })
		-- <C-n> は単バイト制御キーだが、pum 表示中は補完操作として通す
		feed("iJKanji<C-t><C-n><C-b>")
		t.assert_equals(0, selected)
	end)
end)

t.test("unmapped special key is discarded even while pum is visible", function()
	with_buffer(function()
		-- pre-edit 中は補完が自動で pum を開く構成が普通 (lsp.lua は候補が
		-- 無くても [辞書登録] 項目で pum を開く) なので、pum 表示中に
		-- ゲートが素通しになると実環境ではほぼ常に無防備になってしまう
		vim.opt_local.completeopt = "menuone,noselect"
		-- <C-t> は skkelua が上書きしない未マップキー (単バイトなのでゲート対象外)
		vim.cmd("inoremap <buffer> <C-t> <Cmd>call complete(col('.'), ['候補一', '候補二'])<CR>")
		feed("iJKanji<C-t><C-.>")
		t.assert_equals({ "▽かんじ" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("pum navigation keys still work during pre-edit", function()
	with_buffer(function()
		vim.opt_local.completeopt = "menuone,noselect"
		vim.cmd("inoremap <buffer> <C-t> <Cmd>call complete(col('.'), ['候補一', '候補二'])<CR>")
		-- <Down> は選択を動かすだけで挿入はしないため、feed 中に選択状態を
		-- キャプチャして観測する (ゲートに食われていれば noselect の -1 のまま)
		local selected
		vim.keymap.set("i", "<C-b>", function()
			selected = vim.fn.complete_info({ "selected" }).selected
		end, { buffer = true })
		feed("iJKanji<C-t><Down><C-b>")
		t.assert_equals(0, selected)
	end)
end)

t.test("<C-u> clears the pre-edit", function()
	with_buffer(function()
		-- 変換入力中の <C-u> は pre-edit 全体を削除し、続きは通常入力になる
		feed("iJKanji<C-u>nn")
		t.assert_equals({ "ん" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("<C-u> keeps native behavior in direct mode", function()
	with_buffer(function()
		-- 確定済みテキストに対しては native の <C-u> (入力文字の削除) が走る
		feed("iJkaki<C-u>nn")
		t.assert_equals({ "ん" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("unmapped special keys act normally in direct mode", function()
	with_buffer(function()
		-- pre-edit を表示していなければゲートは働かず、キー本来の動作に任せる
		-- (<Left> でカーソルが か の前に戻り、ん はそこへ入る)
		feed("iJka<Left>nn")
		t.assert_equals({ "んか" }, vim.fn.getline(1, "$"))
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

t.test("nested registration via the float prompt", function()
	local lib = require("skkelua.store").get_library()
	local prompt = require("skkelua.register_prompt")
	-- Note: with_buffer は使わない。プロンプトのフロートにフォーカスが
	--       ある状態で bwipeout! すると scratch でなくプロンプトの
	--       バッファを消してしまうため、後始末を自前で行う
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	local scratch = vim.api.nvim_get_current_buf()
	local ok, err = pcall(function()
		-- 辞書に無い読みで変換 -> 登録プロンプトが開く
		feed("iJSoto ")
		vim.wait(500, function()
			return prompt._current() ~= nil
		end, 10)
		local outer = prompt._current()
		t.assert_true(outer ~= nil, "outer prompt should open")

		-- プロンプト内でさらに辞書に無い読みを変換 -> ネストして積まれる
		feed(vim.fn.mode() == "i" and "Naka " or "aNaka ")
		vim.wait(500, function()
			local cur = prompt._current()
			return cur ~= nil and cur.win ~= outer.win
		end, 10)
		local inner = prompt._current()
		t.assert_true(inner ~= nil and inner.win ~= outer.win, "nested prompt should open")
		t.assert_true(vim.api.nvim_win_is_valid(outer.win), "outer should stay open")
		t.assert_equals({ "> ▽なか" }, vim.api.nvim_buf_get_lines(outer.buf, 0, -1, false))

		-- ネスト側の確定で辞書登録され、外側プロンプトへ復帰する
		-- (headless では <CR> を撃てないため _confirm で確定する。
		--  外側バッファの pre-edit 置換は feedkeys 経由のため見ない)
		prompt._confirm("中")
		vim.wait(500, function()
			return #lib:get_henkan_result("okurinasi", "なか") > 0
		end, 10)
		t.assert_equals({ "中" }, lib:get_henkan_result("okurinasi", "なか"))
		t.assert_equals(outer.win, prompt._current().win)
	end)
	-- プロンプトが残ると後続テストを汚すため必ず閉じる
	prompt._close()
	vim.cmd("stopinsert")
	pcall(vim.api.nvim_buf_delete, scratch, { force = true })
	if not ok then
		error(err, 0)
	end
end)
