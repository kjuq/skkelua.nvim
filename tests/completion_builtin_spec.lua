local t = require("tests.helper")

local function with_cmp(fn)
	local previous = package.loaded.cmp
	package.loaded.cmp = {
		visible = function()
			return true
		end,
		get_active_entry = function()
			return {
				get_completion_item = function()
					return { label = "漢字" }
				end,
			}
		end,
	}
	local ok, err = pcall(fn)
	package.loaded.cmp = previous
	if not ok then
		error(err)
	end
end

t.test("enabled completion restores automatic cmp confirmation", function()
	with_cmp(function()
		require("skkelua").config({ completion = { enabled = true } })
		local completion = require("skkelua.completion")
		t.assert_equals(true, completion.state().visible)
		t.assert_true(completion.state().selected ~= nil)
		t.assert_equals(
			vim.api.nvim_replace_termcodes("<Cmd>lua require('cmp').confirm({select = true})<CR>", true, false, true),
			completion.confirm()
		)
	end)
end)

t.test("disabled builtin completion preserves automatic cmp confirmation", function()
	with_cmp(function()
		require("skkelua").config({ completion = { enabled = false } })
		local completion = require("skkelua.completion")
		t.assert_equals(true, completion.state().visible)
		t.assert_true(completion.state().selected ~= nil)
		t.assert_equals(
			vim.api.nvim_replace_termcodes("<Cmd>lua require('cmp').confirm({select = true})<CR>", true, false, true),
			completion.confirm()
		)
	end)
end)

t.test("explicit adapter takes priority and unset restores automatic handling", function()
	with_cmp(function()
		local skk = require("skkelua")
		local completion = require("skkelua.completion")
		completion.set_adapter({
			state = function()
				return { visible = false }
			end,
			confirm = function()
				return "custom"
			end,
		})
		for _, enabled in ipairs({ true, false }) do
			skk.config({ completion = { enabled = enabled } })
			t.assert_equals(false, completion.state().visible)
			t.assert_equals("custom", completion.confirm())
		end
		skk.config({ completion = { enabled = true } })
		completion.set_adapter(nil)
		t.assert_equals(true, completion.state().visible)
	end)
end)

t.test("enabled completion prefers pum and preserves registration metadata", function()
	local original = {
		exists = vim.fn.exists,
		visible = vim.fn["pum#visible"],
		info = vim.fn["pum#complete_info"],
		current = vim.fn["pum#current_item"],
	}
	vim.fn.exists = function(name)
		return name == "*pum#visible" and 1 or original.exists(name)
	end
	vim.fn["pum#visible"] = function()
		return true
	end
	vim.fn["pum#complete_info"] = function(fields)
		t.assert_equals({ "pum_visible", "selected", "inserted" }, fields)
		return {
			pum_visible = true,
			selected = 0,
			inserted = "▽かんじ",
		}
	end
	vim.fn["pum#current_item"] = function()
		return { user_data = { lspitem = vim.json.encode({ data = { skkelua = true, register = true } }) } }
	end
	local ok, err = pcall(function()
		with_cmp(function()
			require("skkelua").config({ completion = { enabled = true } })
			local completion = require("skkelua.completion")
			local state = completion.state()
			t.assert_equals("▽かんじ", state.selected.word)
			t.assert_equals(true, completion.is_register_item(state.selected.item))
			t.assert_equals(
				vim.api.nvim_replace_termcodes("<Cmd>call pum#map#confirm()<CR>", true, false, true),
				completion.confirm()
			)
			require("skkelua").config({ completion = { enabled = false } })
			t.assert_equals("▽かんじ", completion.state().selected.word)
		end)
	end)
	vim.fn.exists = original.exists
	vim.fn["pum#visible"] = original.visible
	vim.fn["pum#complete_info"] = original.info
	vim.fn["pum#current_item"] = original.current
	if not ok then
		error(err)
	end
end)
