local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local archive = require("org_markdown.archive")
local datetime = require("org_markdown.utils.datetime")

-- find_archivable_headings tests
T["find_archivable_headings - returns table"] = function()
	local result = archive.find_archivable_headings(30)
	MiniTest.expect.equality(type(result), "table")
end

-- archive_heading tests
T["archive_heading - exists as function"] = function()
	MiniTest.expect.equality(type(archive.archive_heading), "function")
end

-- is_enabled tests
T["is_enabled - returns boolean"] = function()
	local result = archive.is_enabled()
	MiniTest.expect.equality(type(result), "boolean")
end

-- timer management tests
T["timer management - can stop"] = function()
	-- This should not error
	archive.stop_auto_archive()
	-- Note: We don't actually start it in tests to avoid timer side effects
end

return T
