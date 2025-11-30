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
				title = "Calendar Compact Timeline (7 days)",
				source = "calendar",
				filters = {
					date_range = { days = 10, offset = 0 },
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

-- Non-mutating merge that creates a fresh table
local function merge_tables(default, user)
	local result = {}

	-- First, copy all from default
	for k, v in pairs(default) do
		if type(v) == "table" then
			if vim.tbl_islist(v) then
				-- Arrays: deep copy (will be replaced if user provides)
				result[k] = vim.deepcopy(v)
			else
				-- Objects: deep copy (will be merged if user provides)
				result[k] = vim.deepcopy(v)
			end
		else
			result[k] = v
		end
	end

	-- Then, apply user overrides
	for k, v in pairs(user) do
		if type(v) == "table" and type(result[k]) == "table" then
			if vim.tbl_islist(v) then
				-- Arrays: REPLACE entirely
				result[k] = vim.deepcopy(v)
			else
				-- Objects: MERGE recursively
				result[k] = merge_tables(result[k], v)
			end
		else
			result[k] = v
		end
	end

	return result
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

-- Store immutable defaults
M._defaults = vim.deepcopy(M)

-- Clear all config fields from M (they'll be accessed via metatable)
local keys_to_clear = {}
for k in pairs(M) do
	if k ~= "_defaults" then
		table.insert(keys_to_clear, k)
	end
end
for _, k in ipairs(keys_to_clear) do
	M[k] = nil
end

-- Runtime config (created fresh on each setup)
M._runtime = nil

function M.setup(user_config)
	-- Create fresh runtime config
	M._runtime = merge_tables(M._defaults, user_config or {})

	-- Validate views after merging
	if M._runtime.agendas and M._runtime.agendas.views then
		for view_id, view_def in pairs(M._runtime.agendas.views) do
			validate_view(view_id, view_def)
		end
	end

	return M._runtime
end

-- Allow access via config.field (reads from runtime)
setmetatable(M, {
	__index = function(t, k)
		-- Allow direct access to special keys
		if k == "_defaults" or k == "_runtime" or k == "setup" then
			return rawget(t, k)
		end
		-- Fall back to runtime, then defaults
		if t._runtime and t._runtime[k] ~= nil then
			return t._runtime[k]
		end
		return t._defaults[k]
	end,
})

return M
