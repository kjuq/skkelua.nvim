-- skkelua 公開 API とエントリポイント
-- (main.ts + autoload/skkeleton.vim に相当)

local M = {}

local initialized = false

local function termcode(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

--- Vim script 由来の値の truthy 判定 (0 / v:false / 空文字は falsy)
local function is_truthy(v)
	return v ~= nil and v ~= false and v ~= 0 and v ~= "" and v ~= vim.NIL
end

local function emit_user_autocmd(pattern)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = pattern,
		modeline = false,
	})
end

--------------------------------------------------------------------
-- 初期化
--------------------------------------------------------------------

local function init()
	if initialized then
		return
	end
	local config = require("skkelua.config").config
	local store = require("skkelua.store")
	if config.debug then
		vim.print("skkelua: initialize")
		vim.print(config)
	end
	emit_user_autocmd("skkelua-initialize-pre")

	store.init_context()
	store.set_library_initializer(function()
		return require("skkelua.dictionary").load(config.sources)
	end)

	local group = vim.api.nvim_create_augroup("skkelua-internal-state", { clear = true })
	-- Note: 使い終わったステートを初期化する
	--       CmdlineEnterにしてしまうと辞書登録時の呼び出しで壊れる
	--       挿入モードの`<C-o>`(niI)などで解除されると困るのでModeChangedの:nにしておく
	--       SafeStateトランポリンをしているのはプラグインによるModeChangedの呼び出しで
	--       解除されるのを防ぐため
	--       このイベントはユーザーの操作を受け付けるタイミングで呼ばれるので、
	--       そこでNormalなら改めて処理を行う
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "*:n",
		callback = function()
			vim.api.nvim_create_autocmd("SafeState", {
				once = true,
				callback = function()
					if vim.fn.mode() == "n" then
						M.reset()
						M.disable_impl()
					end
				end,
			})
		end,
	})
	-- insert のまま window 切り替えをすると残るので WinLeave でも消す
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			M.reset()
			M.disable_impl()
		end,
	})

	emit_user_autocmd("skkelua-initialize-post")
	initialized = true
end

--------------------------------------------------------------------
-- vim status の収集 (skkeleton#vim_status 相当)
--------------------------------------------------------------------

---@return string, table
local function complete_info()
	if vim.fn.exists("*pum#visible") == 1 and is_truthy(vim.fn["pum#visible"]()) then
		return "pum.vim", vim.fn["pum#complete_info"]({ "pum_visible", "selected" })
	end
	local cmp = package.loaded["cmp"]
	if cmp then
		local ok, visible = pcall(function()
			return cmp.visible()
		end)
		if ok and visible then
			local selected = cmp.get_active_entry() ~= nil
			return "cmp", { pum_visible = true, selected = selected and 1 or -1 }
		end
	end
	return "native", vim.fn.complete_info({ "pum_visible", "selected" })
end

---@class skkelua.VimStatus
---@field prevInput string
---@field completeInfo table
---@field completeType string
---@field mode string

---@return skkelua.VimStatus
function M.vim_status()
	local complete_type, info = complete_info()
	local m = vim.fn.mode()
	local prev_input
	if m == "i" or m == "t" then
		prev_input = vim.fn.getline("."):sub(1, vim.fn.col(".") - 1)
	else
		prev_input = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
	end
	return {
		prevInput = prev_input,
		completeInfo = info,
		completeType = complete_type,
		mode = m,
	}
end

--------------------------------------------------------------------
-- ハンドラ本体 (main.ts の enable/disable/handle 相当)
--------------------------------------------------------------------

---@param opts table
---@return boolean
local function is_opts(opts)
	return type(opts) == "table" and type(opts.key) == "table"
end

---@param completed boolean
---@param complete_type string
---@param notation_str string
---@return string?
local function handle_complete_key(completed, complete_type, notation_str)
	local config = require("skkelua.config").config
	if notation_str == "<cr>" then
		if completed and config.eggLikeNewline then
			if complete_type == "native" then
				return require("skkelua.notation").notation_to_key["<c-y>"]
			elseif complete_type == "pum.vim" then
				return "<Cmd>call pum#map#confirm()"
			elseif complete_type == "cmp" then
				return "<Cmd>lua require('cmp').confirm({select = true})"
			end
		end
	end
	return nil
end

---@param opts table
---@param vim_status skkelua.VimStatus
---@return string
local function handle_impl(opts, vim_status)
	local config = require("skkelua.config").config
	local notation = require("skkelua.notation")
	local store = require("skkelua.store")
	if not is_opts(opts) then
		error("invalid opts: " .. vim.inspect(opts))
	end
	local key_list = {}
	for _, key in ipairs(opts.key) do
		local real_key = notation.notation_to_key[key]
		key_list[#key_list + 1] = (real_key and notation.key_to_notation[real_key]) or key
	end
	local context = store.get_context()
	context.vimMode = vim_status.mode
	if is_truthy(vim_status.completeInfo.pum_visible) then
		if config.debug then
			vim.print("input after complete")
		end
		local notation_str = table.concat(key_list)
		if config.debug then
			vim.print({
				completeType = vim_status.completeType,
				selected = vim_status.completeInfo.selected,
			})
		end
		local handled = handle_complete_key(
			vim_status.completeInfo.selected >= 0,
			vim_status.completeType,
			notation_str
		)
		if type(handled) == "string" then
			require("skkelua.mode").initialize_state_with_abbrev(context, { "converter" })
			context.preEdit:output("")
			return handled
		end
	end
	local before = context.mode
	if opts["function"] and opts["function"] ~= "" then
		local fn = require("skkelua.function").functions()[opts["function"]]
		if not fn then
			error("unknown function: " .. tostring(opts["function"]))
		end
		for _, key in ipairs(key_list) do
			fn(context, key)
		end
	else
		for _, key in ipairs(key_list) do
			require("skkelua.keymap").handle_key(context, key)
		end
	end
	local output = context.preEdit:output(context:to_string())
	if output == "" and before ~= context.mode then
		-- モード変更をステータスライン等に反映させるための no-op 出力
		return " \b"
	end
	return output
end

---@param opts table
---@param vim_status? skkelua.VimStatus
---@return string
local function enable(opts, vim_status)
	local config = require("skkelua.config").config
	local store = require("skkelua.store")
	local old_context = store.get_context()
	local old_state = old_context.state
	if vim.fn.mode() == "R" then
		vim.print("skkelua is not allowed in replace mode")
		return ""
	end
	if (old_state.type ~= "input" or old_state.mode ~= "direct") and vim_status then
		return handle_impl(opts, vim_status)
	end
	-- Note: must set before context initialization
	require("skkelua.kana").set_current_kana_table(config.kanaTable)
	local context = store.init_context()

	emit_user_autocmd("skkelua-enable-pre")

	require("skkelua.option").save_and_set()
	M.map()
	store.status.enabled = true
	local mode_fn = require("skkelua.function").mode_functions()[store.variables.lastMode]
	if mode_fn then
		mode_fn(context, "")
	end
	emit_user_autocmd("skkelua-enable-post")
	return ""
end

---@param opts table
---@param vim_status? skkelua.VimStatus
---@return string
local function disable(opts, vim_status)
	local store = require("skkelua.store")
	local context = store.get_context()
	local state = context.state
	-- Note: plugin/skkelua.lua で定義している物は opts が空なのでこっちは呼ばない
	if (state.type ~= "input" or state.mode ~= "direct") and is_opts(opts) and vim_status then
		return handle_impl(opts, vim_status)
	end
	require("skkelua.function.disable").disable(context)
	return context.preEdit:output(context:to_string())
end

---@param result string
---@return { state: { henkanFeed: string, phase: string }, result: string }
local function build_result(result)
	local store = require("skkelua.store")
	local state = store.get_context().state
	local phase
	if state.type == "input" then
		if state.mode == "okurinasi" then
			phase = "input:okurinasi"
		elseif state.mode == "okuriari" then
			phase = "input:okuriari"
		else
			phase = "input"
		end
	else
		phase = state.type
	end
	-- 公開ステータス (phase() などが読む) へ反映する
	store.status.phase = phase
	store.status.henkanFeed = state.henkanFeed or ""
	return {
		state = {
			henkanFeed = state.henkanFeed or "",
			phase = phase,
		},
		result = result,
	}
end

--- main.ts の dispatcher.handle 相当
---@param func string
---@param opts table
---@param vim_status skkelua.VimStatus
---@return { state: { henkanFeed: string, phase: string }, result: string }
local function handle_request(func, opts, vim_status)
	init()
	local store = require("skkelua.store")
	local util = require("skkelua.util")
	local context = store.get_context()
	-- 補完の後など preEdit とバッファが不一致している状態の時にリセットする
	if vim_status.mode ~= "t" and not util.ends_with(vim_status.prevInput, context:to_string()) then
		require("skkelua.mode").initialize_state_with_abbrev(context, { "converter" })
		context.preEdit:output("")
	end
	if func == "handleKey" then
		return build_result(handle_impl(opts, vim_status))
	elseif func == "setState" or func == "enable" then
		return build_result(enable(opts, vim_status))
	elseif func == "disable" then
		return build_result(disable(opts, vim_status))
	elseif func == "toggle" then
		local no_mode = store.status.mode == ""
		local disabled = no_mode or not store.status.enabled
		if disabled then
			return build_result(enable(opts, vim_status))
		else
			return build_result(disable(opts, vim_status))
		end
	end
	error("Unsupported function: " .. tostring(func))
end

--------------------------------------------------------------------
-- 公開 API
--------------------------------------------------------------------

--- キー・機能のハンドリング (skkeleton#handle 相当)
---@param func string "handleKey" | "enable" | "disable" | "toggle" | "setState"
---@param opts? { key?: string|string[], function?: string, expr?: boolean }
---@return string? opts.expr が真の場合は送出すべきキー列を返す
function M.handle(func, opts)
	local notation = require("skkelua.notation")
	opts = vim.deepcopy(opts or {})
	-- normalize opts.key and convert key to notation
	local key = opts.key
	if type(key) == "string" then
		opts.key = { notation.key_to_notation[key] or key }
	elseif type(key) == "table" then
		local keys = {}
		for _, k in ipairs(key) do
			keys[#keys + 1] = notation.key_to_notation[k] or k
		end
		opts.key = keys
	else
		opts.key = { "" }
	end

	local ret = handle_request(func, opts, M.vim_status())

	local result = ret.result
	local is_cmd = vim.startswith(result, "<Cmd>")

	M.doautocmd()

	if is_truthy(opts.expr) then
		if is_cmd then
			return termcode("<Cmd>") .. result:sub(6) .. termcode("<CR>")
		end
		return result
	end

	if result ~= "" then
		if is_cmd then
			vim.api.nvim_feedkeys(termcode("<Cmd>") .. result:sub(6) .. termcode("<CR>"), "nit", false)
		else
			-- escape_ks=true: UTF-8 文字列に含まれる K_SPECIAL(0x80) をエスケープする
			vim.api.nvim_feedkeys(result, "nit", true)
		end
	end
end

--- skkelua-handled イベントを次のタイミングで発火する
function M.doautocmd()
	vim.defer_fn(function()
		emit_user_autocmd("skkelua-handled")
	end, 1)
end

--- 現在のモードを返す
---@return string "hira"/"kata"/"hankata"/"zenkaku"/"abbrev"、無効時は ""
function M.mode()
	local status = require("skkelua.store").status
	if status.enabled then
		return status.mode
	else
		return ""
	end
end

---@return boolean
function M.is_enabled()
	return require("skkelua.store").status.enabled
end

--- 直近のキー処理後のフェーズを返す
---@return string "input"/"input:okurinasi"/"input:okuriari"/"henkan"/"escape"/""
function M.phase()
	return require("skkelua.store").status.phase
end

--- デフォルトでマップされるキーのリスト (skkeleton#get_default_mapped_keys 相当)
---@return string[]
function M.get_default_mapped_keys()
	local keys = {}
	local chars = "abcdefghijklmnopqrstuvwxyz"
		.. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		.. "1234567890"
		.. [[!"#$%&'()]]
		.. [[,./;:]@[-^\]]
		.. [[>?_+*}`{=~]]
	for c in chars:gmatch(".") do
		keys[#keys + 1] = c
	end
	vim.list_extend(keys, {
		"<lt>",
		"<Bar>",
		"<BS>",
		"<C-h>",
		"<CR>",
		"<Space>",
		"<C-q>",
		"<C-j>",
		"<C-g>",
		"<Esc>",
	})
	return keys
end

--- 現在のバッファに skkelua のキーマッピングを張る
function M.map()
	local notation = require("skkelua.notation")
	local mode = vim.fn.mode()
	if mode == "n" then
		mode = "i"
	end

	require("skkelua.map").save(mode)

	local mapped_keys = require("skkelua.config").config.mappedKeys or M.get_default_mapped_keys()
	for _, c in ipairs(mapped_keys) do
		local k
		if #c > 1 and c:sub(1, 1) == "<" and c:lower() ~= "<bar>" then
			k = notation.key_to_notation[termcode(c)] or c:lower()
		else
			k = c
		end
		local func = "handleKey"
		local plug = vim.fn.maparg(c, mode):match("<Plug>%(skkelua%-(%a+)%)")
		if plug then
			func = plug
		end
		vim.keymap.set(mode, c, function()
			require("skkelua").handle(func, { key = k })
		end, {
			buffer = true,
			nowait = true,
			silent = true,
			desc = ("skkelua %s (%s)"):format(func, k),
		})
	end
end

--- skkelua のバッファローカルマッピングを全て消す
function M.dangerously_clear_buffer_local_mappings()
	local bufnr = vim.api.nvim_get_current_buf()
	for _, mode in ipairs({ "i", "c", "t", "l", "n", "v", "s", "o" }) do
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
			local rhs = m.rhs or ""
			local desc = m.desc or ""
			if rhs:find("skkelua", 1, true) or desc:find("skkelua", 1, true) then
				local ok = pcall(vim.api.nvim_buf_del_keymap, bufnr, mode, m.lhs)
				if not ok then
					vim.notify(
						("[skkelua.dangerously_clear_buffer_local_mappings] failed: %sunmap <buffer> %s"):format(
							mode,
							m.lhs
						),
						vim.log.levels.ERROR
					)
				end
			end
		end
	end
end

--- skkelua を無効化する
--- Note: 変換途中の確定を伴う無効化は handle("disable") を使うこと
function M.disable_impl()
	local status = require("skkelua.store").status
	if status.enabled then
		emit_user_autocmd("skkelua-disable-pre")
		require("skkelua.map").restore()
		require("skkelua.option").restore()
		status.mode = ""
		emit_user_autocmd("skkelua-mode-changed")
		emit_user_autocmd("skkelua-disable-post")
		status.enabled = false
	end
end

--- コンテキストをリセットする (dispatcher.reset 相当)
function M.reset()
	require("skkelua.store").init_context()
end

--------------------------------------------------------------------
-- 設定 API
--------------------------------------------------------------------

--- 設定を反映する (skkeleton#config 相当)
---@param cfg table<string, any>
function M.config(cfg)
	require("skkelua.config").set_config(cfg)
end

--- lazy.nvim などの慣習に合わせたエイリアス
---@param cfg? table<string, any>
function M.setup(cfg)
	if cfg then
		M.config(cfg)
	end
end

---@return skkelua.ConfigOptions
function M.get_config()
	return require("skkelua.config").config
end

--- キーマップを登録する (skkeleton#register_keymap 相当)
---@param state string "input" | "henkan"
---@param key string
---@param func_name any 関数名。falsy なら削除
function M.register_keymap(state, key, func_name)
	local notation = require("skkelua.notation")
	require("skkelua.keymap").register_key_map(state, notation.normalize(key), func_name)
end

--- かなテーブルを登録する (skkeleton#register_kanatable 相当)
---@param table_name string
---@param table_ table<string, any>
---@param create? boolean
function M.register_kanatable(table_name, table_, create)
	require("skkelua.kana").register_kana_table(table_name, table_, create)
end

--- かなテーブルファイルを登録する (skkeleton#register_kanatable_file 相当)
---@param table_name string
---@param path string
---@param encoding? string
---@param create? boolean
function M.register_kanatable_file(table_name, path, encoding, create)
	require("skkelua.kana").load_kana_table_file(table_name, path, encoding or "", create)
end

--- 初期化 (辞書ロード含む) を行う (skkeleton#initialize 相当)
---@param force? boolean
function M.initialize(force)
	if force then
		initialized = false
	end
	init()
	-- NOTE: Initialize dictionary
	require("skkelua.store").get_library()
end

--- deno_kv データベースは Lua 版では非対応
function M.update_database(_path, _encoding, _force)
	vim.notify(
		"skkelua: updateDatabase (deno_kv) is not supported by the lua version",
		vim.log.levels.WARN
	)
end

--------------------------------------------------------------------
-- 補完ソース向け API (main.ts の completion 系 dispatcher 相当)
--------------------------------------------------------------------

--- プリエディット文字列を返す
---@return string
function M.get_pre_edit()
	return require("skkelua.store").get_context():to_string()
end

--- プリエディットの文字数を返す
--- Note: TS 版は UTF-16 長を返すが、Lua 版は文字数を返す
---@return integer
function M.get_pre_edit_length()
	return require("skkelua.util").char_len(M.get_pre_edit())
end

--- 現在の変換入力 (かな) を返す
---@return string
function M.get_prefix()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "input" then
		return ""
	end
	return state.henkanFeed
end

--- 見出しの変換候補を返す
---@param kana string
---@param type_? skkelua.HenkanType
---@return string[]
function M.get_candidates(kana, type_)
	type_ = type_ or "okurinasi"
	local lib = require("skkelua.store").get_library()
	return lib:get_henkan_result(type_, kana)
end

--- 補完候補を返す
---@return skkelua.CompletionData
function M.get_completion_result()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "input" then
		return {}
	end
	local lib = require("skkelua.store").get_library()
	return lib:get_completion_result(state.henkanFeed, state.feed)
end

--- 候補のランクを返す
---@return skkelua.RankData
function M.get_ranks()
	local state = require("skkelua.store").get_context().state
	if state.type ~= "input" then
		return {}
	end
	local lib = require("skkelua.store").get_library()
	return lib:get_ranks(state.henkanFeed)
end

--- 変換結果をユーザー辞書に登録する (補完ソースからの確定用)
---@param midasi string
---@param word string
---@param type_? skkelua.HenkanType
function M.complete_callback(midasi, word, type_)
	type_ = type_ or "okurinasi"
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result(type_, midasi, word)
	local context = require("skkelua.store").get_context()
	context.lastCandidate = {
		type = type_,
		word = midasi,
		candidate = word,
	}
end

--- complete_callback のエイリアス (registerHenkanResult 相当)
---@param midasi string
---@param word string
function M.register_henkan_result(midasi, word)
	M.complete_callback(midasi, word)
end

--- テスト用: vim_status を指定して dispatcher.handle 相当を呼ぶ
---@param func string
---@param opts table
---@param vim_status skkelua.VimStatus
function M._handle_request(func, opts, vim_status)
	return handle_request(func, opts, vim_status)
end

--- テスト用: 内部状態をリセットする
function M._reset_for_test()
	initialized = false
	require("skkelua.store").init_context()
	require("skkelua.store").init_library()
	require("skkelua.function.henkan")._reset()
	require("skkelua.indicator")._reset_for_test()
end

return M
