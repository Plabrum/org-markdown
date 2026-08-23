local M = {}

M.VERSION = "0.1.0"

-- Item fields carried into the JSON output. Everything the in-editor renderer
-- and formatters read off an item is preserved; the transient `node` field
-- (a document tree node with methods/back-refs) is deliberately dropped so the
-- result is a clean, acyclic, serializable value.
local ITEM_FIELDS = {
	"title",
	"state",
	"priority",
	"date",
	"start_time",
	"end_time",
	"all_day",
	"line",
	"file",
	"tags",
	"source",
	"depth",
	"execution",
	"active",
}

-- Recursively project an agenda item onto its serializable fields.
-- Array-typed fields (`tags`, `children`) are marked via `json.array` so they
-- always emit as JSON arrays, even when empty (never `{}`).
local function serialize_item(item)
	local json = require("org_markdown.utils.json")

	local out = {}
	for _, field in ipairs(ITEM_FIELDS) do
		out[field] = item[field]
	end
	out.tags = json.array(item.tags or {})

	local children = json.array({})
	for _, child in ipairs(item.children or {}) do
		children[#children + 1] = serialize_item(child)
	end
	out.children = children

	return out
end

-- Project a compute_view result into a JSON-safe table.
local function serialize_view(computed)
	local json = require("org_markdown.utils.json")

	local groups = json.array({})
	for _, group in ipairs(computed.groups) do
		local items = json.array({})
		for _, item in ipairs(group.items) do
			items[#items + 1] = serialize_item(item)
		end
		groups[#groups + 1] = { key = group.key, items = items }
	end

	return {
		view_id = computed.view_id,
		title = computed.title,
		groups = groups,
	}
end

-- Hand-parse `--view <id>` / `--view=<id>` from a command's args.
local function parse_view_flag(args)
	local i = 1
	while i <= #args do
		local arg = args[i]
		local inline = arg:match("^%-%-view=(.+)$")
		if inline then
			return inline
		elseif arg == "--view" then
			return args[i + 1]
		end
		i = i + 1
	end
	return nil
end

-- Run the agenda pipeline for a configured view and print it as JSON.
local function run_agenda(args)
	local view_id = parse_view_flag(args)
	if not view_id then
		io.stderr:write("org agenda: missing required --view <id>\n")
		return 1
	end

	local config = require("org_markdown.config")
	config.setup({})

	local views = config.agendas and config.agendas.views or {}
	local view_def = views[view_id]
	if not view_def then
		io.stderr:write("org agenda: unknown view '" .. view_id .. "'\n")
		return 1
	end

	local pipeline = require("org_markdown.agenda.pipeline")
	local json = require("org_markdown.utils.json")

	local computed = pipeline.compute_view(view_id, view_def)
	print(json.encode(serialize_view(computed)))
	return 0
end

-- Hand-parse `--key <value>` flags from a command's args, mirroring the
-- lightweight style of parse_view_flag. Bare/unknown flags are reported.
local function parse_flags(args, known)
	local flags = {}
	local i = 1
	while i <= #args do
		local arg = args[i]
		local key = arg:match("^%-%-(.+)$")
		if not key then
			return nil, "unexpected argument '" .. arg .. "'"
		end
		if not known[key] then
			return nil, "unknown flag '--" .. key .. "'"
		end
		local value = args[i + 1]
		if value == nil then
			return nil, "flag '--" .. key .. "' requires a value"
		end
		flags[key] = value
		i = i + 2
	end
	return flags
end

-- Capture content under a heading non-interactively and write it to disk.
-- Resolves template/file/heading from config by --template; explicit --file /
-- --heading / --content override or supply them directly.
local function run_capture(args)
	local flags, err = parse_flags(args, {
		template = true,
		content = true,
		file = true,
		heading = true,
	})
	if not flags then
		io.stderr:write("org capture: " .. err .. "\n")
		return 1
	end

	local config = require("org_markdown.config")
	local compat = require("org_markdown.compat.vim")
	local core = require("org_markdown.capture.core")
	config.setup({})

	-- Default template is a bare body marker; a named template supplies its own.
	local template = "%?"
	local file = flags.file
	local heading = flags.heading

	if flags.template then
		local tpl = config.captures.templates[flags.template]
		if not tpl then
			io.stderr:write("org capture: no template named '" .. flags.template .. "'\n")
			return 1
		end
		template = type(tpl.template) == "function" and tpl.template() or tpl.template
		file = file or tpl.filename
		if heading == nil then
			heading = tpl.heading
		end
	end

	if not file then
		io.stderr:write("org capture: a destination is required (--file or --template)\n")
		return 1
	end

	local text = core.expand_template(template, {
		content = flags.content,
		file = file,
		author = config.captures.author_name,
	})
	if text == "" then
		io.stderr:write("org capture: nothing to capture (empty content)\n")
		return 1
	end

	core.insert_under_heading(file, heading, compat.split(text, "\n"))

	local where = (heading and heading ~= "") and (" under heading '" .. heading .. "'") or ""
	print("Captured to " .. file .. where)
	return 0
end

-- Command registry: name -> { description, run }.
-- `run` receives the pass-through args and returns an integer exit code.
-- New commands added here self-document in `help_text()`.
---@class OrgCliCommand
---@field description string
---@field run fun(args: string[]): integer
---@type table<string, OrgCliCommand>
M.commands = {
	version = {
		description = "Print the org-markdown CLI version",
		run = function(_args)
			print("org " .. M.VERSION)
			return 0
		end,
	},
	agenda = {
		description = "Emit an agenda view as JSON (org agenda --view <id>)",
		run = run_agenda,
	},
	capture = {
		description = "Capture content under a heading (org capture --template <name> ...)",
		run = run_capture,
	},
}

-- Pure: classify argv into an action table. No printing, no os.exit.
function M.parse(argv)
	local first = argv[1]

	if first == nil or first == "--help" or first == "-h" then
		return { action = "help" }
	end

	if first == "--version" or first == "-v" then
		return { action = "version" }
	end

	if M.commands[first] then
		local rest = {}
		for i = 2, #argv do
			rest[#rest + 1] = argv[i]
		end
		return { action = "run", command = first, args = rest }
	end

	return { action = "unknown", command = first }
end

-- Pure: build the usage string from the command registry.
function M.help_text()
	local names = {}
	for name in pairs(M.commands) do
		names[#names + 1] = name
	end
	table.sort(names)

	local lines = {
		"Usage: org <command> [args]",
		"",
		"Commands:",
	}
	for _, name in ipairs(names) do
		lines[#lines + 1] = string.format("  %-12s %s", name, M.commands[name].description)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Options:"
	lines[#lines + 1] = "  -h, --help     Show this help"
	lines[#lines + 1] = "  -v, --version  Show the version"

	return table.concat(lines, "\n")
end

-- Impure runner: dispatch a parsed action and return an integer exit code.
-- The launcher owns os.exit; this module never calls it.
function M.main(argv)
	local parsed = M.parse(argv)

	if parsed.action == "help" then
		print(M.help_text())
		return 0
	end

	if parsed.action == "version" then
		return M.commands.version.run({})
	end

	if parsed.action == "run" then
		return M.commands[parsed.command].run(parsed.args)
	end

	io.stderr:write("org: unknown command '" .. tostring(parsed.command) .. "'\n\n")
	io.stderr:write(M.help_text() .. "\n")
	return 1
end

return M
