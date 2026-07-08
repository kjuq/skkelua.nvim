-- sources のエラー耐性・候補表示のテスト

local t = require("tests.helper")

t.test("skk_server: graceful failure when server is absent", function()
	local Dictionary = require("skkeleton.sources.skk_server").Dictionary
	local dict = Dictionary.new({
		hostname = "127.0.0.1",
		port = 43999, -- 未使用ポート
		requestEnc = "euc-jp",
		responseEnc = "euc-jp",
	})
	-- 接続できなくても空の結果を返す (エラーにしない)
	t.assert_equals({}, dict:get_henkan_result("okurinasi", "てすと"))
	t.assert_equals({}, dict:get_completion_result("てすと", ""))
	dict:close()
end)

t.test("source loading: unknown source is reported", function()
	local dictionary = require("skkeleton.dictionary")
	-- 不正なソース名でもクラッシュせず Library が返る
	local lib = dictionary.load({ "no_such_source" })
	t.assert_true(lib ~= nil)
	t.assert_equals({}, lib:get_henkan_result("okurinasi", "てすと"))
end)

t.test("popup open/close lifecycle", function()
	local popup = require("skkeleton.popup")
	local function fire_handled()
		vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-handled", modeline = false })
	end
	local before = #vim.api.nvim_list_wins()
	popup.open({ "a: 候補1", "s: 候補2" })
	-- 次の skkeleton-handled で開く
	fire_handled()
	t.assert_equals(before + 1, #vim.api.nvim_list_wins())
	-- その次の skkeleton-handled で閉じる
	fire_handled()
	t.assert_equals(before, #vim.api.nvim_list_wins())
end)

t.test("show candidates via popup after threshold", function()
	local lib = require("skkeleton.store").get_library()
	for i = 1, 12 do
		lib:register_henkan_result("okurinasi", "こうほ", "候補" .. i)
	end
	local context = require("skkeleton.context").new()

	-- popup.open をスタブして呼び出しを記録する
	local popup = require("skkeleton.popup")
	local orig_open = popup.open
	local opened = nil
	popup.open = function(list)
		opened = list
	end
	local ok, err = pcall(function()
		-- 初回変換で candidateIndex=0、その後 4 回送りで showCandidatesCount(4) に到達
		t.dispatch(context, ";kouho     ")
	end)
	popup.open = orig_open
	if not ok then
		error(err, 0)
	end

	t.assert_true(opened ~= nil, "popup.open should be called")
	t.assert_equals(7, #opened)
	-- selectCandidateKeys のラベルが付く
	t.assert_equals("a", opened[1]:sub(1, 1))
end)
