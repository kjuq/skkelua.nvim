-- 擬似プリエディット (preedit.ts に相当)
-- 現在の文字列の状態を覚えておいて削除命令 (BS) を発行することで
-- Vim 上に IME の PreEdit を擬似的に実現する

local M = {}

---@class skkelua.PreEdit
---@field private current string
---@field private kakutei string
local PreEdit = {}
PreEdit.__index = PreEdit

function PreEdit.new()
	return setmetatable({
		current = "",
		kakutei = "",
	}, PreEdit)
end

---@param str string
function PreEdit:do_kakutei(str)
	self.kakutei = self.kakutei .. str
end

--- 表示中テキストの追跡を強制的に合わせる。
--- 補完の選択挿入などで pre-edit がバッファ上で直接置き換えられた
--- 場合に、置き換え後のテキストを削除対象として扱うための再同期用
---@param str string
function PreEdit:sync(str)
	self.current = str
end

--- 次の表示状態を受け取り、送出すべきキー列を返す
---@param next_str string
---@return string
function PreEdit:output(next_str)
	local ret
	-- 補完ウィンドウのちらつき防止のため必要のないバックスペースを送らない
	if self.kakutei == "" and vim.startswith(next_str, self.current) then
		ret = next_str:sub(#self.current + 1)
	else
		-- 書記素クラスタ単位で BS を送る (Intl.Segmenter 相当は strcharlen)
		local bs_count = self.current == "" and 0 or vim.fn.strcharlen(self.current)
		ret = ("\b"):rep(bs_count) .. self.kakutei .. next_str
	end
	self.current = next_str
	self.kakutei = ""
	return ret
end

M.PreEdit = PreEdit

return M
