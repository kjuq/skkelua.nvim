-- かな入力・変換ポイント処理 (function/input.ts に相当)

local util = require("skkelua.util")

local M = {}

--- feed が仮名に変換できる場合は確定する
---@param context skkelua.Context
function M.kakutei_feed(context)
	if context.state.type ~= "input" then
		return
	end
	local input_state = context.state
	local feed = input_state.feed
	local queue_as_kana
	for _, e in ipairs(input_state.table) do
		if e[1] == feed then
			queue_as_kana = e[2]
			break
		end
	end
	if type(queue_as_kana) == "table" then
		M.kakutei_kana(input_state, context.preEdit, queue_as_kana[1], "")
	end
end

--- かなを現在のモードに応じた場所へ確定する
---@param state skkelua.InputState
---@param pre_edit skkelua.PreEdit
---@param kana string
---@param feed string
function M.kakutei_kana(state, pre_edit, kana, feed)
	if state.mode == "direct" then
		if state.converter then
			kana = state.converter(kana)
		end
		pre_edit:do_kakutei(kana)
	elseif state.mode == "okurinasi" then
		state.henkanFeed = state.henkanFeed .. kana
	elseif state.mode == "okuriari" then
		if feed ~= "" and state.previousFeed then
			state.henkanFeed = state.henkanFeed .. kana
		else
			state.okuriFeed = state.okuriFeed .. kana
		end
		state.previousFeed = false
	end
	state.feed = feed
end

---@param context skkelua.Context
---@param kana string
---@param feed string
local function do_kakutei(context, kana, feed)
	local config = require("skkelua.config").config
	local state = context.state
	if state.type ~= "input" then
		return
	end
	M.kakutei_kana(state, context.preEdit, kana, feed)
	if state.mode == "okuriari" and feed == "" then
		if util.char_sub(state.okuriFeed, -1) == "っ" then
			-- immediatelyOkuriConvert が有効になっていない場合
			-- 直接入力などで「使った」のように打つ時「つかっ」の段階では変換をしない
			if config.immediatelyOkuriConvert then
				require("skkelua.function.henkan").henkan_first(context, "")
			end
		else
			require("skkelua.function.henkan").henkan_first(context, "")
		end
	end
end

--- KanaResult を処理する (かな確定 or 機能関数の呼び出し)
---@param context skkelua.Context
---@param result skkelua.KanaResult
---@param feed string
function M.accept_result(context, result, feed)
	if type(result) == "table" then
		do_kakutei(context, result[1], result[2])
	else
		local state = context.state
		state.feed = ""
		result(context, feed)
	end
end

--- かな入力の中心ロジック
---@param context skkelua.Context
---@param char string
function M.kana_input(context, char)
	local config = require("skkelua.config").config
	context.state.type = "input"
	local state = context.state

	local lower = config.lowercaseMap[char] or char:lower()
	if not state.directInput and char ~= lower then
		local with_shift = ("<s-%s>"):format(lower)
		local prefix_key = state.feed .. with_shift
		local found_shift = false
		for _, e in ipairs(state.table) do
			if util.starts_with(e[1], prefix_key) then
				found_shift = true
				break
			end
		end
		if found_shift then
			char = with_shift
		else
			M.henkan_point(context)
			M.kana_input(context, lower)
			return
		end
	end

	local next_feed = state.feed .. char
	local found = {}
	for _, e in ipairs(state.table) do
		if util.starts_with(e[1], next_feed) then
			found[#found + 1] = e
		end
	end

	if #found == 1 and found[1][1] == next_feed then
		-- 正確にマッチした場合はそのまま確定
		M.accept_result(context, found[1][2], next_feed)
	elseif #found > 0 then
		-- テーブルに残余があったら feed に積む
		state.feed = next_feed
	elseif state.feed ~= "" then
		-- テーブルとマッチせず feed が存在した場合は
		-- feed を確定し、もう一度 kana_input に通す
		local current
		for _, e in ipairs(state.table) do
			if e[1] == state.feed then
				current = e
				break
			end
		end
		if current then
			M.accept_result(context, current[2], next_feed)
		elseif config.acceptIllegalResult then
			M.kakutei_kana(state, context.preEdit, state.feed, "")
		else
			state.feed = ""
		end
		M.kana_input(context, char)
	else
		-- feed が無い場合 (=テーブルに存在しない文字) はそのまま確定してしまう
		M.kakutei_kana(state, context.preEdit, char, "")
	end
end

--- 変換ポイントを設定する
---@param context skkelua.Context
function M.henkan_point(context)
	if context.state.type ~= "input" then
		return
	end
	local state = context.state
	local found = {}
	for _, e in ipairs(state.table) do
		if util.starts_with(e[1], state.feed) then
			found[#found + 1] = e
		end
	end
	-- don't transition to okuri mode when henkan str is empty
	if state.mode == "okurinasi" and state.henkanFeed == "" then
		return
	end
	if state.mode == "direct" then
		if #found == 0 then
			context:kakutei(state.feed)
			state.feed = ""
		end
		context:kakutei_with_undo_point("")
		state.mode = "okurinasi"
	elseif state.mode == "okurinasi" then
		if state.feed == "" or #found == 0 then
			state.feed = ""
		elseif found[1][1] == state.feed then
			local result = found[1][2]
			if type(result) == "table" then
				state.henkanFeed = state.henkanFeed .. result[1]
			end
			state.feed = ""
		else
			state.previousFeed = true
		end
		state.mode = "okuriari"
	end
end

--- 一文字削除
---@param context skkelua.Context
function M.delete_char(context)
	if context.state.type ~= "input" then
		return
	end
	local state = context.state
	if state.feed ~= "" then
		state.feed = util.char_sub(state.feed, 1, -2)
	elseif state.mode == "okuriari" then
		if state.okuriFeed ~= "" then
			state.okuriFeed = util.char_sub(state.okuriFeed, 1, -2)
		else
			state.mode = "okurinasi"
		end
	elseif state.mode == "okurinasi" then
		if state.henkanFeed ~= "" then
			state.henkanFeed = util.char_sub(state.henkanFeed, 1, -2)
		else
			require("skkelua.mode").initialize_state_with_abbrev(context, { "converter" })
		end
	else
		context:kakutei("\b")
	end
end

--- 接頭辞変換 (">" キー)
---@param context skkelua.Context
---@param key string
function M.prefix(context, key)
	if context.state.type ~= "input" then
		return
	end

	local state = context.state
	if
		not state.directInput
		and state.henkanFeed ~= ""
		and (state.mode == "okurinasi" or state.mode == "okuriari")
	then
		M.accept_result(context, { ">", "" }, "")
		state.affix = "prefix"
		require("skkelua.function.henkan").henkan_first(context, key)
		return
	end

	M.kana_input(context, key)
end

return M
