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
