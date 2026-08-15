local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local cli = require("org_markdown.cli")

-- parse
T["parse - no args yields help"] = function()
	MiniTest.expect.equality(cli.parse({}).action, "help")
end

T["parse - --help yields help"] = function()
	MiniTest.expect.equality(cli.parse({ "--help" }).action, "help")
end

T["parse - --version yields version"] = function()
	MiniTest.expect.equality(cli.parse({ "--version" }).action, "version")
end

T["parse - known subcommand yields run"] = function()
	local result = cli.parse({ "version" })
	MiniTest.expect.equality(result.action, "run")
	MiniTest.expect.equality(result.command, "version")
end

T["parse - unknown subcommand yields unknown"] = function()
	local result = cli.parse({ "bogus" })
	MiniTest.expect.equality(result.action, "unknown")
	MiniTest.expect.equality(result.command, "bogus")
end

-- help_text
T["help_text - lists version command and usage"] = function()
	local text = cli.help_text()
	MiniTest.expect.equality(text:find("version", 1, true) ~= nil, true)
	MiniTest.expect.equality(text:find("Usage:", 1, true) ~= nil, true)
end

return T
