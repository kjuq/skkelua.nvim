-- dictionary_test.ts の移植 (DenoKvDictionary と yaml は対象外)

local t = require("tests.helper")

local Library = require("skkeleton.dictionary").Library
local wrap_dictionary = require("skkeleton.dictionary").wrap_dictionary
local SkkDictionary = require("skkeleton.sources.skk_dictionary").Dictionary
local UserDictionary = require("skkeleton.sources.user_dictionary").Dictionary

t.test("load new JisyoJson", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("newJisyo.json"), "utf-8")
	local manager = Library.new({ dic }, UserDictionary.new())
	t.assert_equals({ "悪" }, manager:get_henkan_result("okuriari", "わるs"))
	t.assert_equals({ "茜" }, manager:get_henkan_result("okurinasi", "あかね"))
end)

t.test("get candidates", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("globalJisyo"), "euc-jp")
	local manager = Library.new({ dic }, UserDictionary.new())
	t.assert_equals({ "テスト" }, manager:get_henkan_result("okuriari", "てすt"))
	t.assert_equals({ "テスト", "test" }, manager:get_henkan_result("okurinasi", "てすと"))
end)

t.test("get candidates with encoding detection", function()
	-- エンコーディング指定なしでも EUC-JP を自動判定できる
	local dic = SkkDictionary.new()
	dic:load(t.testdata("globalJisyo"), "")
	local manager = Library.new({ dic }, UserDictionary.new())
	t.assert_equals({ "テスト" }, manager:get_henkan_result("okuriari", "てすt"))
end)

t.test("get num candidates", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("numJisyo"), "euc-jp")
	local wrapped = wrap_dictionary(dic)
	local manager = Library.new({ wrapped }, UserDictionary.new())
	t.assert_equals({
		"101番",
		"１０１番",
		"一〇一番",
		"百一番",
		"CI番",
		"佰壱番",
	}, manager:get_henkan_result("okurinasi", "101ばん"))
end)

t.test("get num candidates (Kifu)", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("numJisyo"), "euc-jp")
	local wrapped = wrap_dictionary(dic)
	local manager = Library.new({ wrapped }, UserDictionary.new())
	t.assert_equals({ "１一王手" }, manager:get_henkan_result("okurinasi", "11おうて"))
	t.assert_equals({ "111王手" }, manager:get_henkan_result("okurinasi", "111おうて"))
end)

t.test("get candidates from words that include numbers", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("numIncludingJisyo"), "utf-8")
	local wrapped = wrap_dictionary(dic)
	local manager = Library.new({ wrapped }, UserDictionary.new())
	t.assert_equals({ "🐈" }, manager:get_henkan_result("okurinasi", "cat2"))
	t.assert_equals({ "東京都千代田区千代田" }, manager:get_henkan_result("okurinasi", "1000001"))
end)

t.test("register candidate", function()
	local dic = UserDictionary.new()
	local manager = Library.new({}, dic)
	-- most recently registered
	manager:register_henkan_result("okurinasi", "test", "a")
	manager:register_henkan_result("okurinasi", "test", "b")
	t.assert_equals({ "b", "a" }, manager:get_henkan_result("okurinasi", "test"))
	-- and remove duplicate
	manager:register_henkan_result("okurinasi", "test", "a")
	t.assert_equals({ "a", "b" }, manager:get_henkan_result("okurinasi", "test"))
end)

t.test("global/local jisyo interop", function()
	local dic = SkkDictionary.new()
	dic:load(t.testdata("globalJisyo"), "euc-jp")
	local library = Library.new({ dic }, UserDictionary.new())
	library:register_henkan_result("okurinasi", "てすと", "test")

	-- remove dup
	t.assert_equals({ "test", "テスト" }, library:get_henkan_result("okurinasi", "てすと"))

	-- new candidate
	-- user candidates priority is higher than global
	library:register_henkan_result("okurinasi", "てすと", "てすと")
	t.assert_equals(
		{ "てすと", "test", "テスト" },
		library:get_henkan_result("okurinasi", "てすと")
	)
end)

t.test("read/write skk jisyo", function()
	local tmp = t.tempname()
	local f = assert(io.open(tmp, "wb"))
	f:write("\n;; okuri-ari entries.\n;; okuri-nasi entries.\nあ /あ/\n      ")
	f:close()

	-- load
	local dic = UserDictionary.new()
	dic:load({ path = tmp })
	t.assert_equals({ "あ" }, dic:get_henkan_result("okurinasi", "あ"))

	-- save
	dic:register_henkan_result("okurinasi", "あ", "亜")
	dic:save()
	local rf = assert(io.open(tmp, "rb"))
	local data = rf:read("*a")
	rf:close()
	local found
	for line in vim.gsplit(data, "\n") do
		if vim.startswith(line, "あ") then
			found = line
			break
		end
	end
	t.assert_equals("あ /亜/あ/", found)
	os.remove(tmp)
end)

t.test("don't register empty candidate", function()
	local dic = UserDictionary.new()
	dic:register_henkan_result("okurinasi", "ほげ", "")
	dic:register_henkan_result("okuriari", "ほげ", "")
	t.assert_equals({}, dic:get_henkan_result("okurinasi", "ほげ"))
	t.assert_equals({}, dic:get_henkan_result("okuriari", "ほげ"))
end)

t.test("getRanks", function()
	-- ランクは保存されていた順序あるいは登録された時刻で表される
	-- 適切に比較すると最近登録した物ほど先頭に並ぶようにソートできる
	-- 候補は getCompletionResult の結果によりフィルタリングされる
	local dic = UserDictionary.new()
	dic:register_henkan_result("okurinasi", "ほげ", "hoge")
	dic:register_henkan_result("okurinasi", "ぴよ", "piyo")
	vim.wait(3)
	dic:register_henkan_result("okurinasi", "ほげほげ", "hogehoge")
	local a = dic:get_ranks("ほげ")
	table.sort(a, function(x, y)
		return x[2] > y[2]
	end)
	t.assert_equals(
		{ "hogehoge", "hoge" },
		vim.tbl_map(function(e)
			return e[1]
		end, a)
	)

	vim.wait(3)
	dic:register_henkan_result("okurinasi", "ほげ", "hoge")
	local b = dic:get_ranks("ほげ")
	table.sort(b, function(x, y)
		return x[2] > y[2]
	end)
	t.assert_equals(
		{ "hoge", "hogehoge" },
		vim.tbl_map(function(e)
			return e[1]
		end, b)
	)

	local c = dic:get_ranks("ぴよ")
	t.assert_equals(
		{ "piyo" },
		vim.tbl_map(function(e)
			return e[1]
		end, c)
	)
end)

t.test("number conversion internals", function()
	local convert = require("skkeleton.dictionary")._convert_number
	t.assert_equals("１０１番", convert("#1番", "101ばん"))
	t.assert_equals("一〇一番", convert("#2番", "101ばん"))
	t.assert_equals("百一番", convert("#3番", "101ばん"))
	t.assert_equals("CI番", convert("#8番", "101ばん"))
	t.assert_equals("佰壱番", convert("#5番", "101ばん"))
	t.assert_equals("101番", convert("#番", "101ばん"))
	-- 位取り
	t.assert_equals("千二百三十四", convert("#3", "1234"))
	t.assert_equals("一万", convert("#3", "10000"))
	t.assert_equals("二千二十六年", convert("#3年", "2026ねん"))
end)
