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

t.test("fed <BS> from a completion UI replaces the pre-edit", function()
	with_buffer(function()
		-- 外部の補完 UI は、入力を候補で置き換えるために noremap で <BS> と
		-- 候補を feedkeys することがある。
		-- 物理キーではないので guard は破棄しない
		vim.keymap.set("i", "<C-t>", function()
			local keys = vim.api.nvim_replace_termcodes("<BS><BS><BS><BS>漢字", true, true, true)
			vim.api.nvim_feedkeys(keys, "in", false)
		end, { buffer = true })
		feed("iJKanji<C-t>")
		t.assert_equals({ "漢字" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("<BS> reaching the guard unmapped is discarded unless fed", function()
	local guard = require("skkelua.guard")
	local bs = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
	with_buffer(function()
		local results
		vim.keymap.set("i", "<C-b>", function()
			local reg_executing = vim.fn.reg_executing
			vim.fn.reg_executing = function()
				return "q"
			end
			local replayed = guard._on_key(bs, "")
			vim.fn.reg_executing = reg_executing
			results = { typed = guard._on_key(bs, bs), fed = guard._on_key(bs, ""), replayed = replayed }
		end, { buffer = true })
		feed("iJKanji<C-b>")
		-- 物理キーとマクロ再生の <BS> は従来どおり破棄する
		t.assert_equals({ typed = "", replayed = "" }, results)
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

t.test("<C-n> reopens completion after <C-e> closed the pum during pre-edit", function()
	with_buffer(function()
		vim.opt_local.completeopt = "menuone,noselect"
		vim.cmd("inoremap <buffer> <C-t> <Cmd>call complete(col('.'), ['候補一', '候補二'])<CR>")
		-- <C-n> の keyword 補完がマッチするよう、pre-edit と同じ読みで始まる語を置く
		vim.fn.setline(1, { "", "かんじろう" })
		local after
		vim.keymap.set("i", "<C-b>", function()
			after = { pum = vim.fn.pumvisible(), line = vim.fn.getline(1), phase = require("skkelua.store").status.phase }
		end, { buffer = true })
		-- <C-e> で pum を閉じると pumvisible() は 0 になるが、<C-n> は補完の
		-- 開き直しとして通す (以前は敵対的な制御キーとして破棄されていた)
		feed("iJKanji<C-t><C-e><C-n><C-b>")
		t.assert_equals({ pum = 1, line = "▽かんじ", phase = "input:okurinasi" }, after)
	end)
end)

t.test("<C-y> confirms the register completion item", function()
	with_buffer(function()
		vim.opt_local.completeopt = "menuone,noselect"
		-- [辞書登録] 項目と同じ形: word は pre-edit のままで、確定しても
		-- state は変換入力の続きとして保たれる (registerWord へ繋ぐため)。
		-- このとき skkelua は native 確定の raw <C-y> を feed するので、
		-- guard に食われると辞書登録を確定できなくなる (回帰テスト)
		vim.keymap.set("i", "<C-t>", function()
			local item = {
				word = "▽かんじ",
				abbr = "[辞書登録]",
				user_data = {
					nvim = { lsp = { completion_item = { data = { skkelua = true, register = true } } } },
				},
			}
			vim.fn.complete(vim.fn.col(".") - vim.fn.strlen("▽かんじ"), { item })
		end, { buffer = true })
		local pum_after
		vim.keymap.set("i", "<C-b>", function()
			pum_after = vim.fn.pumvisible()
		end, { buffer = true })
		feed("iJKanji<C-t><C-n><C-y><C-b>")
		-- 確定キーが通れば pum は閉じ、pre-edit と state は保たれている
		t.assert_equals(0, pum_after)
		t.assert_equals({ "▽かんじ" }, vim.fn.getline(1, "$"))
		t.assert_equals("input:okurinasi", require("skkelua.store").status.phase)
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

t.test("X purges the candidate pum-focused via insertOnSelect", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")

	with_buffer(function()
		-- insertOnSelect と同じ形の候補 (word がバッファへ挿入され、フォーカスと
		-- 同時に prevInput 不一致で henkan -> direct へリセットされる) を complete() で模擬する
		vim.opt_local.completeopt = "menuone"
		vim.cmd([[inoremap <buffer> <C-t> <Cmd>lua require('_G')._skkelua_test_complete()<CR>]])
		_G._skkelua_test_complete = function()
			local function item(word, candidate)
				return {
					word = word,
					user_data = {
						nvim = {
							lsp = {
								completion_item = {
									data = { skkelua = true, midasi = "かんじ", word = candidate, type = "okurinasi" },
								},
							},
						},
					},
				}
			end
			vim.fn.complete(vim.fn.col(".") - vim.fn.strlen("▼感じ"), {
				item("感じ", "感じ"),
				item("漢字", "漢字"),
			})
		end

		local confirm_msg
		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function(msg)
			confirm_msg = msg
			return 2 -- No (実際の削除は他のテストで確認する)
		end
		local ok, err = pcall(function()
			-- <C-n> で候補をたどってフォーカスし、まだ確定していない状態で X
			feed("iJKanji <C-t><C-n>X")
			t.assert_equals("Really purge? かんじ /漢字/", confirm_msg)
		end)
		vim.fn.confirm = orig_confirm
		_G._skkelua_test_complete = nil
		if not ok then
			error(err, 0)
		end
	end)
end)

t.test("X purging the pum-focused candidate returns to ▽midasi", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")

	with_buffer(function()
		vim.opt_local.completeopt = "menuone"
		vim.cmd([[inoremap <buffer> <C-t> <Cmd>lua require('_G')._skkelua_test_complete()<CR>]])
		_G._skkelua_test_complete = function()
			local function item(word, candidate)
				return {
					word = word,
					user_data = {
						nvim = {
							lsp = {
								completion_item = {
									data = { skkelua = true, midasi = "かんじ", word = candidate, type = "okurinasi", okuri = "" },
								},
							},
						},
					},
				}
			end
			vim.fn.complete(vim.fn.col(".") - vim.fn.strlen("▼感じ"), {
				item("感じ", "感じ"),
				item("漢字", "漢字"),
			})
		end

		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function(...)
			return 1 -- Yes
		end
		local ok, err = pcall(function()
			feed("iJKanji <C-t><C-n>X")
			-- pum が挿入した "漢字" が消え、削除前の未変換の見出し語入力 (▽かんじ) に戻る
			t.assert_equals({ "▽かんじ" }, vim.fn.getline(1, "$"))
			t.assert_equals({ "感じ" }, lib:get_henkan_result("okurinasi", "かんじ"))
		end)
		vim.fn.confirm = orig_confirm
		_G._skkelua_test_complete = nil
		if not ok then
			error(err, 0)
		end
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
	-- close() はウィンドウとバッファの破棄を schedule しているため、
	-- scratch を削除する前に復帰先のウィンドウが戻るのを待つ。
	vim.wait(100)
	vim.cmd("stopinsert")
	pcall(vim.api.nvim_buf_delete, scratch, { force = true })
	if not ok then
		error(err, 0)
	end
end)

t.test("| is inserted as a raw symbol", function()
	with_buffer(function()
		-- <Bar> は "<Bar>" (大文字) のまま流れて小文字表記のテーブルに当たらず、
		-- shift 入力扱いで ▽ が立った上 "<bar>" と挿入されていた (回帰テスト)
		feed("iJa<Bar>i")
		t.assert_equals({ "あ|い" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("| during henkan is appended to the midasi or inserted after kakutei", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")

	with_buffer(function()
		-- ▽ 状態: shift 入力扱いされて送り仮名開始 (*) に化けていた
		feed("iJKanji<Bar>")
		t.assert_equals({ "▽かんじ|" }, vim.fn.getline(1, "$"))
	end)

	with_buffer(function()
		-- ▼ 状態: 候補を確定してから | が入る
		feed("iJKanji <Bar>")
		t.assert_equals({ "漢字|" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("| is converted in zenkaku mode", function()
	with_buffer(function()
		feed("iJL<Bar>")
		t.assert_equals({ "｜" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("< is inserted as a raw symbol", function()
	with_buffer(function()
		-- < はかなテーブルの <s-l> (L → zenkaku) に前方一致して feed に溜まり、
		-- 次のキーで捨てられて消えていた (回帰テスト)
		feed("iJa<lt>i")
		t.assert_equals({ "あ<い" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("< is converted immediately in zenkaku mode", function()
	with_buffer(function()
		-- 以前は rom_zen の <s-a>〜<s-z> にも前方一致して feed に残り、
		-- 次のキーが来るまで生の < が表示されていた
		feed("iJL<lt>")
		t.assert_equals({ "＜" }, vim.fn.getline(1, "$"))
	end)
end)
