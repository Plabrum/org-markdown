local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local archive = require("org_markdown.archive")
local datetime = require("org_markdown.utils.datetime")

-- add_completed_timestamp tests
T["add_completed_timestamp - adds timestamp to DONE heading"] = function()
	local line = "## DONE Task text"
	local result = archive.add_completed_timestamp(line)

	MiniTest.expect.no_equality(result:match("COMPLETED_AT: %[%d%d%d%d%-%d%d%-%d%d%]"), nil)
	MiniTest.expect.no_equality(result:match("## DONE Task text COMPLETED_AT:"), nil)
end

T["add_completed_timestamp - preserves priority"] = function()
	local line = "## DONE [#A] High priority task"
	local result = archive.add_completed_timestamp(line)

	MiniTest.expect.no_equality(result:match("%[#A%]"), nil)
	MiniTest.expect.no_equality(result:match("COMPLETED_AT:"), nil)
end

T["add_completed_timestamp - preserves tracked date"] = function()
	local line = "## DONE Task <2025-12-20>"
	local result = archive.add_completed_timestamp(line)

	MiniTest.expect.no_equality(result:match("<2025%-12%-20>"), nil)
	MiniTest.expect.no_equality(result:match("COMPLETED_AT:"), nil)
end

T["add_completed_timestamp - inserts before tags"] = function()
	local line = "## DONE Task text :work:urgent:"
	local result = archive.add_completed_timestamp(line)

	-- COMPLETED_AT should come before tags
	local completed_pos = result:find("COMPLETED_AT:")
	local tags_pos = result:find(":work:urgent:")
	MiniTest.expect.no_equality(completed_pos, nil)
	MiniTest.expect.no_equality(tags_pos, nil)
	if completed_pos and tags_pos then
		MiniTest.expect.equality(completed_pos < tags_pos, true)
	end
end

T["add_completed_timestamp - preserves all components"] = function()
	local line = "## DONE [#A] Task text <2025-12-20> :work:urgent:"
	local result = archive.add_completed_timestamp(line)

	-- Check all components are present
	MiniTest.expect.no_equality(result:match("## DONE"), nil)
	MiniTest.expect.no_equality(result:match("%[#A%]"), nil)
	MiniTest.expect.no_equality(result:match("Task text"), nil)
	MiniTest.expect.no_equality(result:match("<2025%-12%-20>"), nil)
	MiniTest.expect.no_equality(result:match("COMPLETED_AT:"), nil)
	MiniTest.expect.no_equality(result:match(":work:urgent:"), nil)
end

T["add_completed_timestamp - does not add duplicate"] = function()
	local line = "## DONE Task COMPLETED_AT: [2025-12-20]"
	local result = archive.add_completed_timestamp(line)

	-- Should return line unchanged
	MiniTest.expect.equality(result, line)

	-- Should only have one COMPLETED_AT
	local _, count = result:gsub("COMPLETED_AT:", "")
	MiniTest.expect.equality(count, 1)
end

T["add_completed_timestamp - unchanged if not heading"] = function()
	local line = "Just some text"
	local result = archive.add_completed_timestamp(line)

	MiniTest.expect.equality(result, line)
end

-- extract_completed_date tests
T["extract_completed_date - extracts date"] = function()
	local line = "## DONE Task COMPLETED_AT: [2025-12-20]"
	local result = archive.extract_completed_date(line)

	MiniTest.expect.no_equality(result, nil)
	MiniTest.expect.equality(result.year, 2025)
	MiniTest.expect.equality(result.month, 12)
	MiniTest.expect.equality(result.day, 20)
end

T["extract_completed_date - returns nil without timestamp"] = function()
	local line = "## DONE Task <2025-12-20>"
	local result = archive.extract_completed_date(line)

	MiniTest.expect.equality(result, nil)
end

T["extract_completed_date - returns nil for invalid format"] = function()
	local line = "## DONE Task COMPLETED_AT: [not-a-date]"
	local result = archive.extract_completed_date(line)

	MiniTest.expect.equality(result, nil)
end

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
