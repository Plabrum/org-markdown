local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local archive = require("org_markdown.archive")
local datetime = require("org_markdown.utils.datetime")
local config = require("org_markdown.config")

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

-- Round-trip archiving tests (would have caught the separator + property
-- ordering corruption)
local function with_temp_archive(lines, fn)
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")

	local saved_paths = config.refile_paths
	local saved_archive = vim.deepcopy(config.archive)
	config.refile_paths = { tmpdir }
	config.archive.enabled = true
	config.archive.threshold_days = 30

	local src = tmpdir .. "/notes.md"
	vim.fn.writefile(lines, src)

	local ok, err = pcall(fn, src)

	config.refile_paths = saved_paths
	config.archive = saved_archive
	vim.fn.delete(tmpdir, "rf")

	if not ok then
		error(err)
	end
end

T["archive_all_eligible - removes old DONE block from source"] = function()
	with_temp_archive({
		"# Notes",
		"",
		"## DONE Old task",
		"COMPLETED_AT: [2025-01-01 Wed]",
		"",
		"## TODO Active task",
		"Not done yet",
	}, function(src)
		archive.archive_all_eligible()
		local after = vim.fn.readfile(src)
		local joined = table.concat(after, "\n")
		MiniTest.expect.equality(joined:find("DONE Old task") == nil, true)
		MiniTest.expect.equality(joined:find("TODO Active task") ~= nil, true)
	end)
end

T["archive_all_eligible - preserves blank separator after surviving task"] = function()
	with_temp_archive({
		"# Notes",
		"",
		"## DONE Recent task",
		"COMPLETED_AT: [2025-12-31 Wed]",
		"",
		"## TODO Active task",
	}, function(src)
		config.archive.threshold_days = 30
		archive.archive_all_eligible()
		local after = vim.fn.readfile(src)
		-- Find the COMPLETED_AT line; the following line must be blank, not the
		-- next heading jammed against it.
		for i, l in ipairs(after) do
			if l:find("COMPLETED_AT") then
				MiniTest.expect.equality(after[i + 1], "")
			end
		end
	end)
end

T["archive_heading - archive file separates blocks and keeps property order"] = function()
	with_temp_archive({
		"# Notes",
		"",
		"## DONE First",
		"COMPLETED_AT: [2025-01-01 Wed]",
		"body one",
		"",
		"## DONE Second",
		"COMPLETED_AT: [2025-01-02 Thu]",
		"body two",
	}, function(src)
		archive.archive_all_eligible()
		local af = src:gsub("%.md$", ".archive.md")
		MiniTest.expect.equality(vim.fn.filereadable(af), 1)
		local lines = vim.fn.readfile(af)
		local joined = table.concat(lines, "\n")

		-- Both blocks archived
		MiniTest.expect.equality(joined:find("DONE First") ~= nil, true)
		MiniTest.expect.equality(joined:find("DONE Second") ~= nil, true)

		-- Property stays directly under its heading (verbatim append)
		for i, l in ipairs(lines) do
			if l:find("^## DONE") then
				MiniTest.expect.equality(lines[i + 1]:find("COMPLETED_AT") ~= nil, true)
			end
		end

		-- No run of headings without a blank line between archived blocks:
		-- the separator before the second block must be a blank line.
		local second = nil
		for i, l in ipairs(lines) do
			if l == "## DONE Second" then
				second = i
				break
			end
		end
		MiniTest.expect.equality(second ~= nil, true)
		MiniTest.expect.equality(lines[second - 1], "")
	end)
end

T["archive_all_eligible - leaves DONE parent with incomplete child in place"] = function()
	with_temp_archive({
		"# Notes",
		"",
		"## DONE Parent",
		"COMPLETED_AT: [2025-01-01 Wed]",
		"",
		"### TODO Open subtask",
		"still working",
	}, function(src)
		archive.archive_all_eligible()
		local after = table.concat(vim.fn.readfile(src), "\n")
		-- Parent (and its open child) must remain in source.
		MiniTest.expect.equality(after:find("DONE Parent") ~= nil, true)
		MiniTest.expect.equality(after:find("TODO Open subtask") ~= nil, true)
		-- Nothing should have been archived.
		local af = src:gsub("%.md$", ".archive.md")
		MiniTest.expect.equality(vim.fn.filereadable(af), 0)
	end)
end

T["archive_all_eligible - archives DONE parent when all children complete"] = function()
	with_temp_archive({
		"# Notes",
		"",
		"## DONE Parent",
		"COMPLETED_AT: [2025-01-01 Wed]",
		"",
		"### DONE Finished subtask",
		"COMPLETED_AT: [2025-01-02 Thu]",
	}, function(src)
		archive.archive_all_eligible()
		local after = table.concat(vim.fn.readfile(src), "\n")
		-- Whole subtree moved out of source.
		MiniTest.expect.equality(after:find("DONE Parent") == nil, true)
		MiniTest.expect.equality(after:find("Finished subtask") == nil, true)
		-- Both ended up in the archive as one block.
		local af = src:gsub("%.md$", ".archive.md")
		local arch = table.concat(vim.fn.readfile(af), "\n")
		MiniTest.expect.equality(arch:find("DONE Parent") ~= nil, true)
		MiniTest.expect.equality(arch:find("Finished subtask") ~= nil, true)
	end)
end

return T
