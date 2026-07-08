-- キー表記 (notation) と内部キーコードの相互変換
-- autoload/skkeleton/notation.vim + notation.ts に相当

local M = {}

---@type table<string, string> notation -> 実キーコード
M.notation_to_key = {}
---@type table<string, string> 実キーコード -> notation
M.key_to_notation = {}

local function termcode(notation)
	return vim.api.nvim_replace_termcodes(notation, true, true, true)
end

local function init()
	-- Note: 同じキーコードを持つ notation が複数ある
	--       (<cr>/<return>/<c-m>、<nl>/<c-j>、<bs>/<c-h> など)。
	--       key_to_notation の逆引きはこのリストの順で先勝ちとし、
	--       keymap.lua が使う表記 (<cr>/<nl>/<bs>/<tab>...) が選ばれるようにする
	local names = {
		"<nul>", "<bs>", "<tab>", "<s-tab>", "<nl>", "<ff>", "<cr>", "<return>",
		"<esc>", "<space>", "<s-space>", "<c-space>", "<lt>", "<bslash>", "<bar>",
		"<del>", "<csi>", "<xcsi>", "<eol>", "<up>", "<down>", "<left>", "<right>",
		"<s-up>", "<s-down>", "<s-left>", "<s-right>", "<c-left>", "<c-right>",
		"<help>", "<undo>", "<insert>", "<home>", "<end>", "<pageup>", "<pagedown>",
		"<kup>", "<kdown>", "<kleft>", "<kright>", "<khome>", "<kend>", "<korigin>",
		"<kpageup>", "<kpagedown>", "<kdel>", "<kplus>", "<kminus>", "<kmultiply>",
		"<kdivide>", "<kpoint>", "<kcomma>", "<kequal>", "<kenter>",
	}
	-- Note: <ignore>/<nop> は nvim_replace_termcodes だと空になるため除外している
	for i = 1, 12 do
		names[#names + 1] = ("<f%d>"):format(i)
		names[#names + 1] = ("<s-f%d>"):format(i)
	end
	for i = 0, 9 do
		names[#names + 1] = ("<k%d>"):format(i)
	end
	for i = 0, 25 do
		local c = string.char(97 + i) -- a-z
		names[#names + 1] = ("<s-%s>"):format(c)
		names[#names + 1] = ("<c-%s>"):format(c)
		names[#names + 1] = ("<m-%s>"):format(c)
		names[#names + 1] = ("<a-%s>"):format(c)
		names[#names + 1] = ("<d-%s>"):format(c)
	end

	local n2k = {}
	local k2n = {}
	for _, n in ipairs(names) do
		local k = termcode(n)
		n2k[n] = k
		if k2n[k] == nil then
			k2n[k] = n
		end
	end
	-- 不要な変換を除去 (例: A -> <s-a>)
	for i = 0, 25 do
		k2n[string.char(65 + i)] = nil
	end
	M.notation_to_key = n2k
	M.key_to_notation = k2n
end

--- キー表記を正規化する (skkeleton#notation#normalize 相当)
--- "<C-J>" -> "<c-j>"、"<Space>" -> "<space>" など
---@param key string
---@return string
function M.normalize(key)
	if #key > 1 and key:sub(1, 1) == "<" then
		key = termcode(key)
	end
	if not key:match("^[A-Z]$") then
		key = M.key_to_notation[key] or key
	end
	if #key ~= 1 then
		key = key:lower()
	end
	return key
end

init()

return M
