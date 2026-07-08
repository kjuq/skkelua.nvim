-- グローバル状態の置き場 (store.ts に相当)
-- TS 版の Cell/LazyCell はこのモジュールの関数群で表現する

local M = {}

---@type skkeleton.Context?
local context = nil

--- 現在のコンテキストを返す (無ければ生成)
---@return skkeleton.Context
function M.get_context()
	if not context then
		context = require("skkeleton.context").new()
	end
	return context
end

--- コンテキストを新規作成して差し替える (currentContext.init 相当)
---@return skkeleton.Context
function M.init_context()
	context = require("skkeleton.context").new()
	return context
end

--- コンテキストを差し替える (辞書登録からの復帰用)
---@param ctx skkeleton.Context
function M.set_context(ctx)
	context = ctx
end

---@type skkeleton.Library?
local library = nil
---@type (fun(): skkeleton.Library)?
local library_initializer = nil

--- 現在の辞書ライブラリを返す (currentLibrary.get 相当)
--- setInitializer 済みならそれを使い、無ければ空ライブラリを作る
---@return skkeleton.Library
function M.get_library()
	if not library then
		if library_initializer then
			library = library_initializer()
		else
			local dictionary = require("skkeleton.dictionary")
			local user_dictionary = require("skkeleton.sources.user_dictionary")
			library = dictionary.Library.new({}, user_dictionary.Dictionary.new())
		end
	end
	return library
end

--- 辞書ライブラリの遅延初期化関数を設定する (currentLibrary.setInitializer 相当)
---@param initializer fun(): skkeleton.Library
function M.set_library_initializer(initializer)
	library_initializer = initializer
	library = nil
end

--- 辞書ライブラリを空に初期化する (currentLibrary.init 相当)
function M.init_library()
	local dictionary = require("skkeleton.dictionary")
	local user_dictionary = require("skkeleton.sources.user_dictionary")
	library = dictionary.Library.new({}, user_dictionary.Dictionary.new())
	return library
end

M.variables = {
	lastMode = "hira",
}

return M
