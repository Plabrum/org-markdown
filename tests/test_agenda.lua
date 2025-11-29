local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local agenda = require("org_markdown.agenda")
local config = require("org_markdown.config")

-- Test view configuration validation
T["config validation - valid view config"] = function()
	local test_config = {
		agendas = {
			views = {
				test_view = {
					title = "Test View",
					source = "tasks",
					filters = { states = { "TODO" } },
					sort = { by = "priority", order = "asc" },
					group_by = "state",
					display = { format = "blocks" },
				},
			},
		},
	}

	-- Should not error
	config.setup(test_config)
	MiniTest.expect.equality(config.agendas.views.test_view.title, "Test View")
end

T["config validation - default views exist"] = function()
	-- Reset to defaults
	config.setup({})

	-- Check default views are present
	MiniTest.expect.no_equality(config.agendas.views.tasks, nil)
	MiniTest.expect.no_equality(config.agendas.views.calendar_blocks, nil)
	MiniTest.expect.no_equality(config.agendas.views.calendar_compact, nil)
	MiniTest.expect.equality(config.agendas.views.tasks.source, "tasks")
	MiniTest.expect.equality(config.agendas.views.calendar_blocks.source, "calendar")
	MiniTest.expect.equality(config.agendas.views.calendar_compact.source, "calendar")
end

T["config validation - tabbed view defaults"] = function()
	config.setup({})

	MiniTest.expect.equality(config.agendas.tabbed_view.enabled, true)
	MiniTest.expect.equality(config.agendas.tabbed_view.views[1], "tasks")
	MiniTest.expect.equality(config.agendas.tabbed_view.views[2], "calendar_blocks")
	MiniTest.expect.equality(config.agendas.tabbed_view.views[3], "calendar_compact")
end

T["config validation - custom view override"] = function()
	local test_config = {
		agendas = {
			views = {
				calendar_compact = {
					title = "Next 14 Days",
					source = "calendar",
					filters = { date_range = { days = 14 } },
					sort = { by = "date", order = "asc" },
					group_by = "date",
				},
			},
		},
	}

	config.setup(test_config)
	MiniTest.expect.equality(config.agendas.views.calendar_compact.title, "Next 14 Days")
	MiniTest.expect.equality(config.agendas.views.calendar_compact.filters.date_range.days, 14)
end

T["show_tabbed_agenda - function exists"] = function()
	MiniTest.expect.equality(type(agenda.show_tabbed_agenda), "function")
end

-- Integration test: verify that views with filters can be configured
T["custom view - high priority filter"] = function()
	local test_config = {
		agendas = {
			views = {
				urgent = {
					title = "Urgent Tasks",
					source = "tasks",
					filters = {
						states = { "TODO", "IN_PROGRESS" },
						priorities = { "A", "B" },
					},
					sort = { by = "priority", order = "asc" },
					display = { format = "timeline" },
				},
			},
		},
	}

	config.setup(test_config)

	-- Verify config was merged
	MiniTest.expect.equality(config.agendas.views.urgent.title, "Urgent Tasks")
	MiniTest.expect.equality(#config.agendas.views.urgent.filters.states, 2)
	MiniTest.expect.equality(config.agendas.views.urgent.filters.priorities[1], "A")
end

-- Test that all expected sort fields are valid
T["config validation - all sort fields valid"] = function()
	local valid_sorts = { "priority", "date", "state", "title", "file" }

	for _, sort_field in ipairs(valid_sorts) do
		local test_config = {
			agendas = {
				views = {
					test_sort = {
						title = "Test",
						source = "tasks",
						sort = { by = sort_field, order = "asc" },
					},
				},
			},
		}

		-- Should not warn/error
		config.setup(test_config)
		MiniTest.expect.equality(config.agendas.views.test_sort.sort.by, sort_field)
	end
end

-- Test that all display formats are valid
T["config validation - all display formats valid"] = function()
	local valid_formats = { "blocks", "timeline" }

	for _, format in ipairs(valid_formats) do
		local test_config = {
			agendas = {
				views = {
					test_format = {
						title = "Test",
						source = "tasks",
						display = { format = format },
					},
				},
			},
		}

		-- Should not warn/error
		config.setup(test_config)
		MiniTest.expect.equality(config.agendas.views.test_format.display.format, format)
	end
end

-- Test that all group_by options are valid
T["config validation - all group_by options valid"] = function()
	local valid_groups = { "date", "priority", "state", "file", "tags" }

	for _, group_by in ipairs(valid_groups) do
		local test_config = {
			agendas = {
				views = {
					test_group = {
						title = "Test",
						source = "tasks",
						group_by = group_by,
					},
				},
			},
		}

		-- Should not warn/error
		config.setup(test_config)
		MiniTest.expect.equality(config.agendas.views.test_group.group_by, group_by)
	end
end

-- Test that tabbed agenda still works
T["tabbed agenda - function exists"] = function()
	-- Reset config
	config.setup({})

	-- Verify tabbed agenda function exists
	MiniTest.expect.equality(type(agenda.show_tabbed_agenda), "function")
end

return T
