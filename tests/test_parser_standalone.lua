local MiniTest = require("mini.test")
local T = MiniTest.new_set()

-- These tests prove the parser produces identical output under the standalone
-- CLI runtime (plain luajit, NO `vim` global) as it does in-editor. Rather than
-- trust the in-process parser (which runs with `vim` present), we shell out to a
-- real `luajit` subprocess that asserts `_G.vim == nil`, run the parser there,
-- and compare its output against the SAME expectations `test_parser.lua` uses.

-- Representative headlines and the expectations mirrored from test_parser.lua.
-- The standalone script below prints one field per line; we compare the whole
-- captured stdout against `expected` for an exact parity check.
local expected = table.concat({
	-- parse_headline("# TODO [#A] Write tests :work:urgent:")
	"TODO",
	"A",
	"Write tests",
	"work",
	"urgent",
	-- parse_headline("# IN_PROGRESS Refactor parser :dev:")
	"IN_PROGRESS",
	"nil",
	"Refactor parser",
	"dev",
	-- parse_headline("# DONE [#B] Completed work :done:")
	"DONE",
	"B",
	"Completed work",
	-- extract_date("- [ ] TODO task <2025-06-22> [2025-06-23]")
	"2025-06-22",
	"2025-06-23",
}, "\n") .. "\n"

-- The script executed by the standalone luajit subprocess. `%s` is the repo cwd.
local script_template = [[
package.path = "%s/lua/?.lua;%s/lua/?/init.lua;" .. package.path
assert(_G.vim == nil, "vim global must be absent in standalone runtime")
local parser = require("org_markdown.utils.parser")

local h1 = parser.parse_headline("# TODO [#A] Write tests :work:urgent:")
local t1 = parser.extract_tags("# TODO [#A] Write tests :work:urgent:")
print(h1.state)
print(h1.priority)
print(h1.text)
print(t1[1])
print(t1[2])

local h2 = parser.parse_headline("# IN_PROGRESS Refactor parser :dev:")
local t2 = parser.extract_tags("# IN_PROGRESS Refactor parser :dev:")
print(h2.state)
print(tostring(h2.priority))
print(h2.text)
print(t2[1])

local h3 = parser.parse_headline("# DONE [#B] Completed work :done:")
print(h3.state)
print(h3.priority)
print(h3.text)

local tracked, untracked = parser.extract_date("- [ ] TODO task <2025-06-22> [2025-06-23]")
print(tracked)
print(untracked)
]]

T["parser output parity under standalone luajit"] = function()
	if vim.fn.executable("luajit") ~= 1 then
		MiniTest.skip("luajit not available on PATH")
		return
	end

	local cwd = vim.fn.getcwd()
	local script = string.format(script_template, cwd, cwd)

	-- List form avoids shell quoting; run with a clean env so no `vim` leaks in.
	local output = vim.fn.system({ "luajit", "-e", script })

	MiniTest.expect.equality(vim.v.shell_error, 0)
	MiniTest.expect.equality(output, expected)
end

return T
