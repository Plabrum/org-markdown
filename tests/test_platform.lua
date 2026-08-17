local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Exercise the pure/standalone backend directly so these assertions hold
-- regardless of the runtime chosen by platform/init.lua.
local standalone = require("org_markdown.platform.standalone")

local T = MiniTest.new_set()

-- path.expand
T["path.expand"] = MiniTest.new_set()

T["path.expand"]["expands a leading tilde"] = function()
	local home = os.getenv("HOME")
	MiniTest.expect.equality(standalone.path.expand("~"), home)
	MiniTest.expect.equality(standalone.path.expand("~/notes"), home .. "/notes")
end

T["path.expand"]["expands environment variables"] = function()
	local home = os.getenv("HOME")
	MiniTest.expect.equality(standalone.path.expand("$HOME/notes"), home .. "/notes")
	MiniTest.expect.equality(standalone.path.expand("${HOME}/notes"), home .. "/notes")
end

T["path.expand"]["leaves a plain path unchanged"] = function()
	MiniTest.expect.equality(standalone.path.expand("/abs/path"), "/abs/path")
end

-- path.basename
T["path.basename"] = MiniTest.new_set()

T["path.basename"]["returns the final component"] = function()
	MiniTest.expect.equality(standalone.path.basename("/a/b/c.md"), "c.md")
	MiniTest.expect.equality(standalone.path.basename("c.md"), "c.md")
end

-- path.relative
T["path.relative"] = MiniTest.new_set()

T["path.relative"]["strips the cwd prefix"] = function()
	local cwd = standalone.fs.cwd()
	MiniTest.expect.equality(standalone.path.relative(cwd .. "/sub/file.md"), "sub/file.md")
	MiniTest.expect.equality(standalone.path.relative(cwd), ".")
end

T["path.relative"]["uses ~ for paths under home"] = function()
	local home = os.getenv("HOME")
	-- Only meaningful when home is not itself the cwd prefix.
	if home and standalone.fs.cwd():sub(1, #home + 1) ~= home .. "/" then
		MiniTest.expect.equality(standalone.path.relative(home .. "/deep/x.md"), "~/deep/x.md")
	end
end

-- fs.scandir
T["fs.scandir"] = MiniTest.new_set()

T["fs.scandir"]["lists files and directories with types"] = function()
	local workspace = helpers.create_temp_workspace({
		["top.md"] = "# Top",
		["nested/inner.md"] = "# Inner",
	})

	local entries = standalone.fs.scandir(workspace)

	local by_name = {}
	for _, entry in ipairs(entries) do
		by_name[entry.name] = entry.type
	end

	MiniTest.expect.equality(by_name["top.md"], "file")
	MiniTest.expect.equality(by_name["nested"], "directory")

	helpers.cleanup_temp(workspace)
end

T["fs.scandir"]["includes dotfiles and excludes . and .."] = function()
	local workspace = helpers.create_temp_workspace({
		[".hidden.md"] = "# Hidden",
	})

	local entries = standalone.fs.scandir(workspace)

	local names = {}
	for _, entry in ipairs(entries) do
		names[entry.name] = true
	end

	MiniTest.expect.equality(names[".hidden.md"], true)
	MiniTest.expect.equality(names["."], nil)
	MiniTest.expect.equality(names[".."], nil)

	helpers.cleanup_temp(workspace)
end

T["fs.scandir"]["returns empty list for a missing directory"] = function()
	local entries = standalone.fs.scandir("/no/such/dir/really/here")
	MiniTest.expect.equality(#entries, 0)
end

-- fs.read_file / fs.write_file
T["fs read/write"] = MiniTest.new_set()

T["fs read/write"]["round-trips file content"] = function()
	local workspace = helpers.create_temp_workspace({})
	local path = workspace .. "/roundtrip.md"

	local ok = standalone.fs.write_file(path, "hello\nworld")
	MiniTest.expect.equality(ok, true)

	local content = standalone.fs.read_file(path)
	MiniTest.expect.equality(content, "hello\nworld")

	helpers.cleanup_temp(workspace)
end

T["fs read/write"]["read_file returns nil + err for a missing file"] = function()
	local content, err = standalone.fs.read_file("/no/such/file.md")
	MiniTest.expect.equality(content, nil)
	MiniTest.expect.equality(type(err), "string")
end

-- init.lua backend selection
T["init selects the nvim backend in-editor"] = function()
	local platform = require("org_markdown.platform")
	-- These tests run under Neovim, so the shim must expose the full surface.
	MiniTest.expect.equality(type(platform.fs.scandir), "function")
	MiniTest.expect.equality(type(platform.path.expand), "function")
	MiniTest.expect.equality(type(platform.notify), "function")
end

return T
