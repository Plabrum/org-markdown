-- Configuration management with deep merge and path expansion
-- Responsibilities:
-- - Define default configuration with all available options
-- - Deep merge user config with defaults (objects merge, arrays replace)
-- - Integrate with neoconf for project-specific settings
-- - Expand ~/org/ paths throughout config based on org_dir
-- - Validate agenda view definitions
-- - Provide helper methods for accessing ordered views

local compat = require("org_markdown.compat.vim")
local platform = require("org_markdown.platform")

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
		-- Patterns to exclude from agenda scanning. Ingestion logs live under
		-- `sources/`: their entries are raw source material, and only become
		-- agenda items once promoted out of the log.
		ignore_patterns = { "*.archive.md", "sources/*" },
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
		insert_link = "<leader>oil",
		follow_link = "<leader>ol",
		backlinks = "<leader>ob",
		open_quick_note = "<leader>z",
		sync_all = "<leader>oS",
		start_task = "<leader>oxs",
		pause_task = "<leader>oxp",
		done_task = "<leader>oxd",
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
		notification_level = compat.log_levels.INFO,
	},

	execution = {
		-- Append-only log of task state transitions. Execution state is never
		-- stored on the heading; it is derived by folding this log.
		log_file = "~/org/execution.log",
	},

	promotion = {
		-- Where an ingested source entry lands when it is promoted, unless the
		-- caller names a destination of its own. It has to be a file the agenda
		-- scans -- promotion is what moves an item into planning.
		-- A `heading` can be set to land promoted items under one heading.
		file = "~/org/refile.md",
		status = "TODO",
	},

	archive = {
		enabled = true, -- Enable archiving feature (timestamp addition)
		auto_archive = false, -- Disable auto-archive by default (user must opt-in)
		interval = 86400000, -- Check every 24 hours (milliseconds)
		initial_delay = 5000, -- Delay before first auto-archive sweep after startup (ms)
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
			if compat.tbl_islist(v) then
				-- Arrays: deep copy (will be replaced if user provides)
				result[k] = compat.deepcopy(v)
			else
				-- Objects: deep copy (will be merged if user provides)
				result[k] = compat.deepcopy(v)
			end
		else
			result[k] = v
		end
	end

	-- Then, apply user overrides
	for k, v in pairs(user) do
		if type(v) == "table" and type(result[k]) == "table" then
			if compat.tbl_islist(v) then
				-- Arrays: REPLACE entirely
				result[k] = compat.deepcopy(v)
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

	if view_def.source and not compat.tbl_contains({ "tasks", "calendar", "all" }, view_def.source) then
		table.insert(warnings, "Invalid source: " .. view_def.source)
	end

	if view_def.sort and view_def.sort.by then
		if not compat.tbl_contains({ "priority", "date", "state", "title", "file" }, view_def.sort.by) then
			table.insert(warnings, "Invalid sort.by: " .. view_def.sort.by)
		end
	end

	if view_def.group_by then
		if not compat.tbl_contains({ "date", "priority", "state", "file", "tags" }, view_def.group_by) then
			table.insert(warnings, "Invalid group_by: " .. view_def.group_by)
		end
	end

	if view_def.display and view_def.display.format then
		if not compat.tbl_contains({ "blocks", "timeline" }, view_def.display.format) then
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
		platform.notify(
			string.format("View '%s' warnings:\n%s", view_id, table.concat(warnings, "\n")),
			compat.log_levels.WARN
		)
	end
end

-- Store immutable defaults
M._defaults = compat.deepcopy(M)

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

-- Environment variable naming a Lua-chunk config file. When set (and readable),
-- setup() loads it as the base user config. The in-editor side writes its live
-- resolved config to a temp file and passes this var when spawning the `org`
-- CLI, so the standalone process reproduces the editor's config (custom
-- refile_paths, views, ignore_patterns, ...) instead of only knowing defaults.
--
-- A Lua chunk (`return { ... }`) is used rather than JSON so it loads with a
-- bare `loadfile` under plain luajit -- no standalone JSON decoder required.
M.ENV_CONFIG = "ORG_MARKDOWN_CONFIG"

--- Load the config referenced by $ORG_MARKDOWN_CONFIG, if any.
--- Standalone-safe: uses only `loadfile`/`os.getenv`, never `vim.*`.
---@return table|nil config, string|nil err
local function load_env_config()
	local path = os.getenv(M.ENV_CONFIG)
	if not path or path == "" then
		return nil
	end

	local chunk, load_err = loadfile(path)
	if not chunk then
		return nil, "could not load " .. M.ENV_CONFIG .. " (" .. tostring(load_err) .. ")"
	end

	local ok, result = pcall(chunk)
	if not ok then
		return nil, M.ENV_CONFIG .. " chunk errored: " .. tostring(result)
	end
	if type(result) ~= "table" then
		return nil, M.ENV_CONFIG .. " did not return a table"
	end

	return result
end

-- Helper to get views as an ordered array (for iteration/tabs)
-- Returns array of { id = "view_id", ...view_def }
function M.get_ordered_views()
	if not M._runtime or not M._runtime.agendas or not M._runtime.agendas.views then
		return {}
	end

	local views = {}
	for view_id, view_def in pairs(M._runtime.agendas.views) do
		local view = compat.deepcopy(view_def)
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

	-- Base the config on $ORG_MARKDOWN_CONFIG when present (used by the CLI to
	-- inherit the live editor config); explicit user_config still layers on top.
	local env_config, env_err = load_env_config()
	if env_err then
		platform.notify("org_markdown: " .. env_err, compat.log_levels.ERROR)
	end
	if env_config then
		user_config = merge_tables(env_config, user_config or {})
	end

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
