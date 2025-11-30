local M = {
	captures = {
		window_method = "horizontal",
		default_template = "todo",

		-- Author name for %n template marker
		-- Defaults to git config user.name, then $USER if not set
		author_name = nil,

		-- Available template markers:
		-- %t - Active timestamp: <2025-11-29 Fri>
		-- %T - Active timestamp with time: <2025-11-29 Fri 14:30>
		-- %u - Inactive timestamp: [2025-11-29 Fri]
		-- %U - Inactive timestamp with time: [2025-11-29 Fri 14:30]
		-- %H - Time only: 14:30 (renamed from old %t to avoid conflict)
		-- %n - Author name (from config.author_name, git config, or $USER)
		-- %Y - Year: 2025
		-- %m - Month: 11
		-- %d - Day: 29
		-- %f - Current file relative path
		-- %F - Current file absolute path
		-- %a - Link to current file and line: [[file:/path/to/file.md +123]]
		-- %x - Clipboard contents
		-- %? - Cursor position after template expansion
		-- %^{prompt} - Prompt user for input with label
		-- %<fmt> - Custom date format (e.g., %<%Y-%m-%d %H:%M:%S>)

		templates = {
			["todo"] = {
				template = "# TODO %? \n %u",
				filename = "~/notes/todo.md",
				heading = "TODO's",
			},
			["notes"] = {
				template = "#  %?",
				filename = "~/notes/notes.md",
				heading = "Notes",
			},
		},
	},
	agendas = {
		window_method = "float",
		views = {
			tasks = {
				title = "Tasks (by priority)",
				source = "tasks",
				filters = {},
				sort = {
					by = "priority",
					order = "asc",
					priority_rank = { A = 1, B = 2, C = 3, Z = 99 },
				},
				group_by = nil,
				display = { format = "timeline" },
			},
			calendar_blocks = {
				title = "Calendar Blocks (7 days)",
				source = "calendar",
				filters = {
					date_range = { days = 7, offset = 0 },
				},
				sort = {
					by = "date",
					order = "asc",
				},
				group_by = "date",
				display = { format = "blocks" },
			},
			calendar_compact = {
				title = "Calendar Compact Timeline (14 days)",
				source = "calendar",
				filters = {
					date_range = { days = 14, offset = 0 },
				},
				sort = {
					by = "date",
					order = "asc",
				},
				group_by = "date",
				display = { format = "timeline" },
			},
		},
		tabbed_view = {
			enabled = true,
			views = { "tasks", "calendar_blocks", "calendar_compact" },
		},
	},
	window_method = "vertical",
	picker = "snacks", -- or "telescope"
	-- picker = "telescope",
	refile_paths = { "~/notes" },
	quick_note_file = "~/notes/quick_notes/",
	sync = {
		enabled = true,
		plugins = {
			-- Plugins will register their default config here
		},
		sync_all_command = "MarkdownSyncAll",
	},
	keymaps = {
		capture = "<leader>oc",
		agenda = "<leader>oa",
		find_file = "<leader>of",
		find_heading = "<leader>oh",
		refile_to_file = "<leader>orf",
		refile_to_heading = "<leader>orh",
		open_quick_note = "<leader>z",
		sync_all = "<leader>oS",
	},
	checkbox_states = {
		" ",
		"-",
		"X",
	},
	status_states = {
		"TODO",
		"IN_PROGRESS",
		"DONE",
	},

	-- TODO PAL: Implement front matter automations
	-- automation = {
	-- 	tags = {
	-- 		moab = {
	-- 			on_enter = function(filename)
	-- 				return vim.fn.input("Tag: ")
	-- 			end,
	-- 			on_exit = function(filename) end,
	-- 		},
	-- 	},
	-- },
}

local function merge_tables(default, user)
	for k, v in pairs(user) do
		if type(v) == "table" and type(default[k]) == "table" then
			merge_tables(default[k], v)
		else
			default[k] = v
		end
	end
end

local function validate_view(view_id, view_def)
	local warnings = {}

	if view_def.source and not vim.tbl_contains({ "tasks", "calendar", "all" }, view_def.source) then
		table.insert(warnings, "Invalid source: " .. view_def.source)
	end

	if view_def.sort and view_def.sort.by then
		if not vim.tbl_contains({ "priority", "date", "state", "title", "file" }, view_def.sort.by) then
			table.insert(warnings, "Invalid sort.by: " .. view_def.sort.by)
		end
	end

	if view_def.group_by then
		if not vim.tbl_contains({ "date", "priority", "state", "file", "tags" }, view_def.group_by) then
			table.insert(warnings, "Invalid group_by: " .. view_def.group_by)
		end
	end

	if view_def.display and view_def.display.format then
		if not vim.tbl_contains({ "blocks", "timeline" }, view_def.display.format) then
			table.insert(warnings, "Invalid display.format: " .. view_def.display.format)
		end
	end

	if #warnings > 0 then
		vim.notify(string.format("View '%s' warnings:\n%s", view_id, table.concat(warnings, "\n")), vim.log.levels.WARN)
	end
end

function M.setup(user_config)
	merge_tables(M, user_config or {})

	-- Validate views after merging
	if M.agendas and M.agendas.views then
		for view_id, view_def in pairs(M.agendas.views) do
			validate_view(view_id, view_def)
		end
	end
end

return M
