-- グローバル状態の置き場 (store.ts に相当)
-- TS 版の Cell/LazyCell はこのモジュールの関数群で表現する

local M = {}

---@type skkelua.Context?
local context = nil

--- 現在のコンテキストを返す (無ければ生成)
---@return skkelua.Context
function M.get_context()
	if not context then
		context = require("skkelua.context").new()
	end
	return context
end

--- コンテキストを新規作成して差し替える (currentContext.init 相当)
---@return skkelua.Context
function M.init_context()
	context = require("skkelua.context").new()
	return context
end

--- コンテキストを差し替える (辞書登録からの復帰用)
---@param ctx skkelua.Context
function M.set_context(ctx)
	context = ctx
end

---@type skkelua.Library?
local library = nil
---@type (fun(): skkelua.Library)?
local library_initializer = nil

--- 現在の辞書ライブラリを返す (currentLibrary.get 相当)
--- setInitializer 済みならそれを使い、無ければ空ライブラリを作る
---@return skkelua.Library
function M.get_library()
	if not library then
		if library_initializer then
			library = library_initializer()
		else
			local dictionary = require("skkelua.dictionary")
			local user_dictionary = require("skkelua.sources.user_dictionary")
			library = dictionary.Library.new({}, user_dictionary.Dictionary.new())
		end
	end
	return library
end

--- 辞書ライブラリの遅延初期化関数を設定する (currentLibrary.setInitializer 相当)
---@param initializer fun(): skkelua.Library
function M.set_library_initializer(initializer)
	library_initializer = initializer
	library = nil
end

--- 辞書ライブラリを空に初期化する (currentLibrary.init 相当)
function M.init_library()
	local dictionary = require("skkelua.dictionary")
	local user_dictionary = require("skkelua.sources.user_dictionary")
	library = dictionary.Library.new({}, user_dictionary.Dictionary.new())
	return library
end

M.variables = {
	lastMode = "hira",
}

-- 公開ステータス (require("skkelua") の mode()/is_enabled()/phase() が読む)
---@class skkelua.Status
---@field enabled boolean
---@field mode string 現在の入力モード。無効時は ""
---@field phase string 直近のキー処理後のフェーズ
---@field henkanFeed string
M.status = {
	enabled = false,
	mode = "",
	phase = "",
	henkanFeed = "",
}

return M
