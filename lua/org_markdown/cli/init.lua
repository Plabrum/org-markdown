local M = {}

M.VERSION = "0.1.0"

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
