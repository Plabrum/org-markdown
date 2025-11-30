local MiniTest = require("mini.test")
local config = require("org_markdown.config")

local T = MiniTest.new_set()

T["setup"] = function()
	-- Save original defaults
	T.original_defaults = vim.deepcopy(config._defaults)
end

T["teardown"] = function()
	-- Restore defaults
	config._defaults = T.original_defaults
	config._runtime = nil
end

T["merge"] = MiniTest.new_set()

T["merge"]["doesn't mutate defaults"] = function()
	local before = vim.deepcopy(config._defaults)

	config.setup({
		captures = {
			author_name = "Test User",
		},
	})

	local after = config._defaults

	MiniTest.expect.equality(before, after, "Defaults should not be mutated")
end

T["merge"]["allows multiple setups"] = function()
	config.setup({ captures = { author_name = "First" } })
	local first_name = config.captures.author_name

	config.setup({ captures = { author_name = "Second" } })
	local second_name = config.captures.author_name

	MiniTest.expect.equality(first_name, "First")
	MiniTest.expect.equality(second_name, "Second")
end

T["merge"]["replaces arrays instead of merging"] = function()
	-- Default checkbox_states = {" ", "-", "X"}
	config.setup({
		checkbox_states = { " ", "x" }, -- User provides 2 states
	})

	local states = config.checkbox_states
	-- Arrays should be REPLACED, not merged
	MiniTest.expect.equality(#states, 2, "Should replace, not merge")
	MiniTest.expect.equality(states[1], " ")
	MiniTest.expect.equality(states[2], "x")
end

T["merge"]["views array replacement"] = function()
	config.setup({
		agendas = {
			views = {
				{
					id = "custom",
					title = "Custom View",
					source = "tasks",
				},
			},
		},
	})

	-- Views is an array - should be REPLACED, not merged
	MiniTest.expect.equality(#config.agendas.views, 1, "Should replace entire array")
	MiniTest.expect.equality(config.agendas.views[1].id, "custom")
	MiniTest.expect.equality(config.agendas.views[1].title, "Custom View")
end

T["validation"] = MiniTest.new_set()

T["validation"]["accepts any window_method (no validation)"] = function()
	-- Current implementation doesn't validate window_method
	local ok = pcall(config.setup, {
		window_method = "invalid_method",
	})

	MiniTest.expect.equality(ok, true, "Accepts any window_method value")
	MiniTest.expect.equality(config.window_method, "invalid_method")
end

T["validation"]["accepts any picker (no validation)"] = function()
	-- Current implementation doesn't validate picker
	local ok = pcall(config.setup, {
		picker = "invalid_picker",
	})

	MiniTest.expect.equality(ok, true, "Accepts any picker value")
	MiniTest.expect.equality(config.picker, "invalid_picker")
end

return T
