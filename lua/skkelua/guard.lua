-- 未マップの特殊キーから pre-edit を守るゲート
--
-- skkelua は「処理できるキーだけをバッファローカルにマップする」方式のため、
-- マップ外の特殊キー (<C-.> や <Left> など) は Neovim にそのまま処理されて
-- バッファと pre-edit の追跡がずれ、次のキー処理時の prevInput 不一致リセット
-- で ▽/▼ マーカーがゴミとして取り残される。かといって特殊キーを全て列挙して
-- マップするのは、修飾キーの組み合わせが実質無限にあるため成立しない
-- (<Tab> の passThrough 保護や <S-CR> の個別マップと同じいたちごっこになる)。
--
-- そこで vim.on_key で全入力を監視し、pre-edit 表示中に「マッピングに消費され
-- ずに素通りしてきた物理特殊キー」だけを破棄する。既存の passThrough (変換中
-- は何もしない) の意味論を、キーを列挙せずに特殊キー全体へ一般化したものに
-- 相当する。キーの破棄 (コールバックが "" を返す) は Neovim 0.10+ の機能で、
-- それ未満では返り値が無視されるため従来通りの挙動に戻るだけで害はない。

local M = {}

local ns = vim.api.nvim_create_namespace("skkelua.guard")

local function termcode(notation)
	return vim.api.nvim_replace_termcodes(notation, true, true, true)
end

-- KS_EXTRA (0x80 0xfd) は <Cmd>/KE_LUA (Lua コールバックマッピング) /
-- FocusGained などの内部擬似キーと物理キーが混在しており、未知のコードまで
-- 破棄すると Neovim の内部動作を壊しかねない。そのため KS_EXTRA に限っては
-- 物理キー由来と分かっているものだけを列挙して破棄する。
-- なお修飾キー付き特殊キーの大半 (<C-Up> など) は KS_MODIFIER プレフィックス
-- で表現されるため列挙不要で、ここに並ぶのは専用コードを持つ少数派のみ
---@type table<string, boolean>?
local extra_physical
---@return table<string, boolean>
local function extra_physical_keys()
	if extra_physical then
		return extra_physical
	end
	extra_physical = {}
	local names = { "<s-up>", "<s-down>", "<s-left>", "<s-right>", "<c-left>", "<c-right>" }
	for i = 1, 12 do
		names[#names + 1] = ("<s-f%d>"):format(i)
	end
	for _, n in ipairs(names) do
		extra_physical[termcode(n)] = true
	end
	return extra_physical
end

-- pum 表示中でも補完の操作として意味を持つキー
-- (<C-n>/<C-p>/<C-e>/<C-y> は単バイト制御キー側の破棄対象なのでここで救う)
-- Note: <C-y> は skkelua 自身も feed する: [辞書登録] 項目の確定では
--       native_confirm_key が raw <C-y> を feedkeys し、しかも登録フローへ
--       繋ぐため state は非 direct のまま保たれる。ここで通さないと
--       辞書登録を <C-y> で確定できなくなる
---@type table<string, boolean>?
local pum_nav
---@return table<string, boolean>
local function pum_nav_keys()
	if pum_nav then
		return pum_nav
	end
	pum_nav = {}
	for _, n in ipairs({ "<up>", "<down>", "<pageup>", "<pagedown>", "<c-n>", "<c-p>", "<c-e>", "<c-y>" }) do
		pum_nav[termcode(n)] = true
	end
	return pum_nav
end

-- skkelua 自身が pre-edit の更新のために feed する制御バイト
-- (<C-g>u の undo 区切り、\b による削除、改行・Tab・Esc)。
-- これらのキーをユーザーが打った場合はマップ済みキーとして KE_LUA 擬似キー
-- 側で消費されるので、生のまま許可しても防御は緩まない
local OWN_OUTPUT_BYTES = {
	[0x07] = true, -- <C-g> (undo 区切り <C-g>u)
	[0x08] = true, -- \b (pre-edit の削除)
	[0x09] = true, -- <Tab>
	[0x0a] = true, -- <NL>
	[0x0d] = true, -- <CR>
	[0x1b] = true, -- <Esc>
}

--- pre-edit を壊しうる単バイトの制御キーかどうか
---
--- <C-r> (レジスタ貼り付け)・<C-k> (digraph)・<C-v> (リテラル入力) などは
--- K_SPECIAL ではなく単バイト (0x00-0x1f, 0x7f) で届く。skkelua 自身の
--- feed 出力にも制御バイトが含まれるため全部は破棄できないが、自前出力に
--- 現れるバイトは OWN_OUTPUT_BYTES の固定集合に限られるので、それ以外を
--- 破棄対象にできる
---@param key string
---@return boolean
function M._is_hostile_control(key)
	if #key ~= 1 then
		return false
	end
	local b = key:byte(1)
	if b > 0x1f and b ~= 0x7f then
		return false
	end
	return not OWN_OUTPUT_BYTES[b]
end

--- 物理キー由来の K_SPECIAL シーケンスかどうか
---@param key string on_key に渡された (マッピング適用後の) 生キー
---@return boolean
function M._is_physical_special(key)
	if key:byte(1) ~= 0x80 then
		-- 通常の文字入力と skkelua 自身の出力 (かな・\b など) はここで抜ける
		return false
	end
	local b2 = key:byte(2)
	if b2 == 0xfe then
		-- KS_SPECIAL: 本文中の 0x80 バイトのエスケープ (escape_ks=true で
		-- feedkeys した "　" などの UTF-8 継続バイト)。キーではなく本文
		return false
	end
	if b2 == 0xfd then
		return extra_physical_keys()[key] == true
	end
	-- KS_MODIFIER (0xfc: <C-.> など修飾キー全般) と termcap 系 (<Up>/<Del>/
	-- <F5> など) はすべて物理キー。skkelua の出力や内部擬似キーには現れない
	return true
end

---@param key string マッピング適用後のキー。マップ済みキーは KE_LUA 擬似キー
---                   として現れるため、ここに生の特殊キーが来る = 未マップで
---                   素通りする直前ということ
---@return string? "" を返すとそのキーは破棄される
function M._on_key(key, _)
	if not M._is_physical_special(key) and not M._is_hostile_control(key) then
		return
	end
	local store = require("skkelua.store")
	if not store.status.enabled then
		return
	end
	local state = store.get_context().state
	if state.type == "input" and state.mode == "direct" then
		-- pre-edit を表示していない直接入力中はキー本来の動作に任せる
		return
	end
	-- 補完ポップアップ表示中は候補選択キーだけを通す。pre-edit 中は補完が
	-- 自動で pum を開く構成が普通 (lsp.lua は候補が無くても [辞書登録] 項目
	-- で pum を開く) なので、pum 表示中の全面バイパスはゲートを実質無効化
	-- してしまう。選択挿入などでバッファが変わるケースは既存の補完リカバリ
	-- (prevInput 不一致リセット) が面倒を見る
	if vim.fn.pumvisible() == 1 and pum_nav_keys()[key] then
		return
	end
	-- pre-edit 状態のまま insert を抜けた場合 (stopinsert など) に
	-- ノーマルモードのキーまで食わないための保険
	local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
	if mode ~= "i" and mode ~= "c" and mode ~= "t" then
		return
	end
	return ""
end

--- ゲートを有効にする (同じ namespace への登録は上書きなので再入可)
function M.attach()
	vim.on_key(M._on_key, ns)
end

--- ゲートを無効にする
function M.detach()
	vim.on_key(nil, ns)
end

return M
