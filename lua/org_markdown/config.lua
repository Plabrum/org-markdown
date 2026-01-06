-- Configuration management with deep merge and path expansion
-- Responsibilities:
-- - Define default configuration with all available options
-- - Deep merge user config with defaults (objects merge, arrays replace)
-- - Integrate with neoconf for project-specific settings
-- - Expand ~/org/ paths throughout config based on org_dir
-- - Validate agenda view definitions
-- - Provide helper methods for accessing ordered views

local M = {
	-- Base directory for org files
	-- Used as default for:
	-- - captures.templates.*.filename (~/org/...)
	-- - refile_paths (~/org)
	-- - quick_note_file (~/org/quick_notes/)
	-- - folding.enabled_paths (~/org/**)
	-- Change this to customize where your org files live
	org_dir = "~/org",

	captures = {
		window_method = "horizontal",
		default_template = "Task",
		start_in_insert = false, -- Start capture buffer in insert mode

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
		-- %<fmt> - Custom date format (e.g., %<%Y-%m-%d %a> for 2025-11-29 Fri)

		templates = {
			["Task"] = {
				template = "# TODO %? \nCREATED_AT: %u",
				filename = "~/org/refile.md",
				heading = "",
			},
		},
	},
	agendas = {
		window_method = "float",
		ignore_patterns = { "*.archive.md" }, -- Patterns to exclude from agenda scanning
		views = {
			tasks = {
				order = 1,
				title = "Tasks",
				source = "tasks",
				filters = {
					states = { "TODO", "IN_PROGRESS" },
				},
				sort = {
					by = "file",
					order = "asc",
				},
				group_by = "file",
				display = { format = "timeline" },
			},
			calendar = {
				order = 2,
				title = "Calendar (10-Day Timeline)",
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
			inbox = {
				order = 3,
				title = "Refile Inbox",
				source = "all",
				filters = {
					file_patterns = { "refile" }, -- Flexible pattern matching
					states = { "TODO", "IN_PROGRESS" },
				},
				sort = {
					by = "date",
					order = "asc",
				},
				group_by = "file",
				display = { format = "timeline" },
			},
		},
	},
	window_method = "vertical",
	picker = "snacks", -- or "telescope"
	-- picker = "telescope",
	refile_paths = { "~/org" },
	refile_heading_ignore = { "calendar", "archive/*" }, -- List of patterns to exclude from refile heading operations (e.g., "calendar.md", "archive/*")
	quick_note_file = "~/org/quick_notes/",
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
		find_file = "<leader>off",
		find_heading = "<leader>ofh",
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
		"IN_REVIEW",
		"DONE",
		"CANCELLED",
	},
	status_colors = {
		TODO = "red",
		IN_PROGRESS = "yellow",
		IN_REVIEW = "green",
		DONE = "blue",
		CANCELLED = "gray",
	},
	folding = {
		enabled = true, -- Enable folding features
		auto_fold_on_open = true, -- Fold all headings when file opens (ignored if remember_folds is true)
		remember_folds = true, -- Remember fold level per file (overrides auto_fold_on_open)
		enabled_paths = { "~/org/**" }, -- List of path patterns to enable folding (nil = all markdown files)
		fold_on_tab = true, -- Use Tab for heading fold cycling
		global_fold_on_shift_tab = true, -- Use Shift-Tab for global fold cycling
	},
	notifications = {
		enabled = true,
		intervals = { 10, 2 },
		cache_refresh_interval = 300,
		auto_refresh_on_save = false,
		max_lookahead_days = 7,
		notification_format = "%s in %d minutes",
		notification_level = vim.log.levels.INFO,
	},

	archive = {
		enabled = true, -- Enable archiving feature (timestamp addition)
		auto_archive = false, -- Disable auto-archive by default (user must opt-in)
		interval = 86400000, -- Check every 24 hours (milliseconds)
		threshold_days = 30, -- Archive DONE items older than 30 days
		archive_suffix = ".archive", -- Suffix for archive files
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

	-- Check for deprecated filters.files field
	if view_def.filters and view_def.filters.files then
		table.insert(
			warnings,
			"filters.files is deprecated. Use filters.file_patterns instead for flexible pattern matching."
		)
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

-- Register with neoconf for autocomplete (only runs once)
local neoconf_registered = false
local function register_neoconf()
	if neoconf_registered then
		return
	end
	local ok, neoconf_plugins = pcall(require, "neoconf.plugins")
	if ok then
		neoconf_plugins.register({
			name = "org_markdown",
			on_schema = function(schema)
				schema:import("org_markdown", M._defaults)
			end,
		})
		neoconf_registered = true
	end
end

--- Recursively expand ~/org/ paths in config based on org_dir
--- @param value any Config value (can be table, string, or other)
--- @param org_dir string The org_dir to expand to
--- @return any Expanded value
local function expand_org_paths(value, org_dir)
	if type(value) == "string" then
		-- Expand ~/org/ prefix in strings
		if value:match("^~/org/") or value == "~/org" or value:match("^~/org%*%*") then
			return value:gsub("^~/org", org_dir)
		end
		return value
	elseif type(value) == "table" then
		-- Recursively expand tables
		local expanded = {}
		for k, v in pairs(value) do
			expanded[k] = expand_org_paths(v, org_dir)
		end
		return expanded
	else
		-- Other types pass through unchanged
		return value
	end
end

-- Helper to get views as an ordered array (for iteration/tabs)
-- Returns array of { id = "view_id", ...view_def }
function M.get_ordered_views()
	if not M._runtime or not M._runtime.agendas or not M._runtime.agendas.views then
		return {}
	end

	local views = {}
	for view_id, view_def in pairs(M._runtime.agendas.views) do
		local view = vim.deepcopy(view_def)
		view.id = view_id
		table.insert(views, view)
	end

	-- Sort by order field (default to 999 if not specified, then alphabetically)
	table.sort(views, function(a, b)
		local order_a = a.order or 999
		local order_b = b.order or 999
		if order_a == order_b then
			return a.id < b.id
		end
		return order_a < order_b
	end)

	return views
end

function M.setup(user_config)
	-- Register schema for autocomplete
	register_neoconf()

	-- Try to load neoconf settings if available
	local neoconf_config = {}
	local ok, neoconf = pcall(require, "neoconf")
	if ok then
		neoconf_config = neoconf.get("org_markdown") or {}
	end

	-- Merge: defaults < user_config < neoconf (neoconf has highest priority)
	local merged = merge_tables(M._defaults, user_config or {})
	M._runtime = merge_tables(merged, neoconf_config)

	-- Expand ~/org/ paths throughout the config based on org_dir
	if M._runtime.org_dir then
		M._runtime = expand_org_paths(M._runtime, M._runtime.org_dir)
	end

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
		-- Priority: runtime > directly set values > defaults
		if t._runtime and t._runtime[k] ~= nil then
			return t._runtime[k]
		end
		local direct_value = rawget(t, k)
		if direct_value ~= nil then
			return direct_value
		end
		return t._defaults[k]
	end,
	__newindex = function(t, k, v)
		-- Direct assignment updates runtime config (if it exists)
		if t._runtime then
			t._runtime[k] = v
		else
			-- Before setup, write to the table directly
			rawset(t, k, v)
		end
	end,
})

return M
