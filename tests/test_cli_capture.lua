local MiniTest = require("mini.test")
local T = MiniTest.new_set()

-- Covers the vim-free capture core (shared by capture.lua and the `org capture`
-- CLI) plus an end-to-end standalone run of the CLI itself. The core is exercised
-- in-process (platform/compat delegate to vim here); the CLI test shells out to a
-- real `luajit` so it proves the mutation works with NO Neovim.

local core = require("org_markdown.capture.core")

local function write_file(path, content)
	local f = assert(io.open(path, "w"))
	f:write(content)
	f:close()
end

local function read_file(path)
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	return content
end

local function tmpfile()
	return vim.fn.tempname() .. ".md"
end

-- expand_template ----------------------------------------------------------

T["expand_template - %? resolves to supplied content"] = function()
	local out = core.expand_template("- %?", { content = "Buy milk" })
	MiniTest.expect.equality(out, "- Buy milk")
end

T["expand_template - content with % is inserted verbatim"] = function()
	local out = core.expand_template("%?", { content = "50% done" })
	MiniTest.expect.equality(out, "50% done")
end

T["expand_template - interactive/clipboard markers vanish headlessly"] = function()
	-- %^{label} prompt and %x clipboard have no headless equivalent -> "".
	local out = core.expand_template("a%^{Tag}b%xc", {})
	MiniTest.expect.equality(out, "abc")
end

T["expand_template - %n falls back to $USER or User"] = function()
	local out = core.expand_template("%n", { author = "Alice" })
	MiniTest.expect.equality(out, "Alice")
	local fallback = core.expand_template("%n", {})
	MiniTest.expect.equality(fallback ~= "" and fallback ~= "%n", true)
end

-- insert_under_heading -----------------------------------------------------

T["insert_under_heading - inserts under an existing heading"] = function()
	local path = tmpfile()
	write_file(path, "# Journal\n\n## Tasks\n\n# Other\n")

	core.insert_under_heading(path, "Tasks", { "Buy milk" })

	local result = read_file(path)
	MiniTest.expect.equality(result:find("## Tasks\n\nBuy milk", 1, true) ~= nil, true)
	-- The unrelated heading is preserved.
	MiniTest.expect.equality(result:find("# Other", 1, true) ~= nil, true)
	os.remove(path)
end

T["insert_under_heading - creates a missing heading"] = function()
	local path = tmpfile()
	write_file(path, "# Journal\n")

	core.insert_under_heading(path, "Inbox", { "captured note" })

	local result = read_file(path)
	MiniTest.expect.equality(result:find("# Inbox", 1, true) ~= nil, true)
	MiniTest.expect.equality(result:find("captured note", 1, true) ~= nil, true)
	os.remove(path)
end

T["insert_under_heading - creates a missing file"] = function()
	local path = tmpfile()
	os.remove(path) -- ensure it does not exist

	core.insert_under_heading(path, "Tasks", { "first entry" })

	local result = read_file(path)
	MiniTest.expect.equality(result:find("# Tasks", 1, true) ~= nil, true)
	MiniTest.expect.equality(result:find("first entry", 1, true) ~= nil, true)
	os.remove(path)
end

-- End-to-end CLI (standalone luajit, no Neovim) ----------------------------

T["org capture inserts under a heading with no Neovim"] = function()
	if vim.fn.executable("luajit") ~= 1 then
		MiniTest.skip("luajit not available on PATH")
		return
	end

	local path = tmpfile()
	write_file(path, "# Journal\n\n## Tasks\n\n# Other\n")

	local cwd = vim.fn.getcwd()
	local out = vim.fn.system({
		cwd .. "/bin/org",
		"capture",
		"--file",
		path,
		"--heading",
		"Tasks",
		"--content",
		"Buy milk from the CLI",
	})

	MiniTest.expect.equality(vim.v.shell_error, 0)
	MiniTest.expect.equality(out:find("Captured to", 1, true) ~= nil, true)

	local result = read_file(path)
	MiniTest.expect.equality(result:find("## Tasks\n\nBuy milk from the CLI", 1, true) ~= nil, true)
	MiniTest.expect.equality(result:find("# Other", 1, true) ~= nil, true)
	os.remove(path)
end

return T
