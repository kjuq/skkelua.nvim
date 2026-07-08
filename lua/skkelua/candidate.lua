-- 候補の表示・確定用の加工 (candidate.ts に相当)

local M = {}

--- 注釈 (;以降) を除去し、接辞変換なら > を取り除く
---@param candidate string?
---@param affix? "prefix"|"suffix"
---@return string?
function M.modify_candidate(candidate, affix)
	if candidate == nil then
		return nil
	end
	local stripped = candidate:gsub(";.*", "")
	if affix == "prefix" then
		return (stripped:gsub(">$", ""))
	elseif affix == "suffix" then
		return (stripped:gsub("^>", ""))
	else
		return stripped
	end
end

return M
