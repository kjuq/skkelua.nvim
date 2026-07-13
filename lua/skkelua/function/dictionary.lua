-- 辞書登録プロンプト (function/dictionary.ts に相当)

local M = {}

local cmap_keys = { "<Esc>", "<C-g>" }

--- cmdline 版の辞書登録プロンプト (vim.fn.input)。
--- cmdline モード中の変換からの登録で使う (insert バッファへ移動できないため)
---@param context skkelua.Context
---@return boolean 登録して確定した場合 true
local function register_word_cmdline(context)
	local config = require("skkelua.config").config
	local store = require("skkelua.store")
	local mode_mod = require("skkelua.mode")
	local state = context.state --[[@as skkelua.HenkanState]]

	require("skkelua.map").save("c")
	for _, k in ipairs(cmap_keys) do
		vim.keymap.set("c", k, "__skkelua_return__<CR>", { buffer = true, silent = true })
	end

	-- Note: use virtualedit for fix slip cursor position at line ending.
	local save_virtualedit = vim.api.nvim_get_option_value("virtualedit", { win = 0 })
	vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })

	local registered = false
	local ok, err = pcall(function()
		local base = "[辞書登録] " .. state.henkanFeed
		local okuri = state.mode == "okuriari" and ("*" .. state.okuriFeed) or ""
		store.init_context()
		vim.api.nvim_create_autocmd("CmdlineEnter", {
			once = true,
			callback = function()
				require("skkelua").map()
			end,
		})
		local input = vim.fn.input(base .. okuri .. ": ")
		if input == "" or input:find("__skkelua_return__", 1, true) then
			vim.cmd("echo '' | redraw")
			return
		end
		state.candidates = { input }
		state.candidateIndex = 0
		require("skkelua.function.common").kakutei(context)
		registered = true
	end)
	if not ok and config.debug then
		vim.print("registerWord interrupted")
		vim.print(err)
	end

	-- 後始末 (TS 版の finally 節に相当)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkelua-enable-pre",
		modeline = false,
	})
	-- restore skkelua mode
	require("skkelua").map()
	require("skkelua.store").status.enabled = true
	vim.cmd.redrawstatus()
	vim.api.nvim_set_option_value("virtualedit", save_virtualedit, { win = 0 })
	-- restore stashed context
	store.set_context(context)
	-- and mode
	mode_mod.mode_change(context, context.mode)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "skkelua-enable-post",
		modeline = false,
	})

	return registered
end

--- フロート版の辞書登録プロンプト。
--- insert モードのバッファで skkelua + 補完メニューを使って入力できる。
--- 確定・キャンセルは非同期 (コールバック) で処理するため、呼び出し時点で
--- 登録に必要な情報をすべてキャプチャし、変換状態は破棄する
---@param context skkelua.Context
---@return boolean 常に true (プロンプトを開いた)
local function register_word_float(context)
	local store = require("skkelua.store")
	local state = context.state --[[@as skkelua.HenkanState]]
	local win = vim.api.nvim_get_current_win()
	local mode = context.mode
	local okuri = state.mode == "okuriari" and ("*" .. state.okuriFeed) or ""
	local title = "[辞書登録] " .. state.henkanFeed .. okuri

	-- 登録・置換に必要な情報のキャプチャ
	local type_ = state.mode
	local midasi = state.word
	local okuri_str = state.converter and state.converter(state.okuriFeed) or state.okuriFeed
	local affix = state.affix
	local shown = context.preEdit:shown() -- バッファに表示中の pre-edit

	-- キャンセル時に変換入力状態 (▽よみ) を復元するためのキャプチャ
	local saved = {
		mode = state.mode,
		henkanFeed = state.henkanFeed,
		okuriFeed = state.okuriFeed,
		feed = state.feed,
		previousFeed = state.previousFeed,
		converter = state.converter,
		table = state.table,
		directInput = state.directInput,
		affix = state.affix,
	}

	-- handle の後処理がバッファへ出力しないよう、状態と表示追跡を空にする。
	-- バッファ上の pre-edit はそのまま残し、確定時に自前の BS 列で置換する
	require("skkelua.mode").initialize_state_with_abbrev(context)
	context.preEdit:sync("")
	store.init_context()

	--- 元のウィンドウへ戻り、skkelua を有効化し直す。
	--- フロートへの移動時にバッファ離脱の自動 disable が走っているため、
	--- 正規の enable フローで補完の attach ごと復活させる
	local function back_to_window()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
		end
		require("skkelua").handle("enable", {})
		require("skkelua.mode").mode_change(store.get_context(), mode)
		vim.cmd.redrawstatus()
	end

	--- cmdline 版のキャンセルと同様に、変換入力状態 (▽よみ) へ戻す。
	--- バッファに残っている pre-edit を追跡し直してから復元後の表示へ置換する。
	--- Note: enable が state を作り直すため、復元は back_to_window の後に行う
	local function restore_henkan_input()
		back_to_window()
		local ctx = store.get_context()
		for k, v in pairs(saved) do
			ctx.state[k] = v
		end
		ctx.state.type = "input"
		-- 手動復元では build_result を通らないため、補完 (make_completion_list)
		-- が参照する公開ステータスも合わせて復元する
		store.status.phase = saved.mode == "okuriari" and "input:okuriari" or "input:okurinasi"
		store.status.henkanFeed = saved.henkanFeed
		ctx.preEdit:sync(shown)
		local keys = ctx.preEdit:output(ctx:to_string())
		vim.api.nvim_feedkeys("a" .. keys, "nit", true)
		-- タイプを伴わない復元では補完の autotrigger が働かないため、
		-- キー処理が終わって insert に入ったところで明示的にトリガーする
		vim.api.nvim_create_autocmd("SafeState", {
			once = true,
			callback = function()
				require("skkelua.lsp").trigger()
			end,
		})
	end

	-- 呼び出し元のキー処理 (handle) が完了してからフロートを開く
	vim.schedule(function()
		require("skkelua.register_prompt").open({
			title = title,
			on_confirm = function(input)
				-- 空入力はキャンセル扱い (cmdline 版と同じ)
				if input == "" then
					restore_henkan_input()
					return
				end
				back_to_window()
				local lib = store.get_library()
				lib:register_henkan_result(type_, midasi, input)
				store.get_context().lastCandidate = {
					type = type_,
					word = midasi,
					candidate = input,
				}
				local candidate = require("skkelua.candidate").modify_candidate(input, affix) or input
				-- normal に戻っているので "a" で pre-edit 直後から insert に
				-- 入り、表示中だった pre-edit を消して登録結果に置き換える
				local bs = ("\b"):rep(vim.fn.strcharlen(shown))
				vim.api.nvim_feedkeys("a" .. bs .. candidate .. okuri_str, "nit", true)
			end,
			on_cancel = restore_henkan_input,
		})
	end)
	return true
end

--- 辞書登録プロンプトを開く
---@param context skkelua.Context
---@return boolean cmdline 版は登録して確定した場合 true。
---フロート版は開いた時点で true (結果はコールバックで処理される)
function M.register_word(context)
	if context.vimMode == "c" then
		return register_word_cmdline(context)
	end
	return register_word_float(context)
end

return M
