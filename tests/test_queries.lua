local MiniTest = require("mini.test")
local helpers = require("helpers")
local queries = require("org_markdown.utils.queries")
local config = require("org_markdown.config")

local T = MiniTest.new_set()

T["find_markdown_files"] = MiniTest.new_set()

T["find_markdown_files"]["finds .md files recursively"] = function()
	local workspace = helpers.create_temp_workspace({
		["notes/file1.md"] = "# Note 1",
		["notes/subdir/file2.md"] = "# Note 2",
		["notes/file3.txt"] = "Not markdown",
		["notes/file4.markdown"] = "# Note 4",
	})

	-- Save and override config
	local original_paths = config.refile_paths
	config.refile_paths = { workspace }

	local files = queries.find_markdown_files()

	-- Restore config
	config.refile_paths = original_paths

	-- Should find 3 markdown files
	MiniTest.expect.equality(#files, 3)

	local basenames = vim.tbl_map(function(f)
		return vim.fn.fnamemodify(f, ":t")
	end, files)

	MiniTest.expect.equality(vim.tbl_contains(basenames, "file1.md"), true)
	MiniTest.expect.equality(vim.tbl_contains(basenames, "file2.md"), true)
	MiniTest.expect.equality(vim.tbl_contains(basenames, "file4.markdown"), true)

	helpers.cleanup_temp(workspace)
end

T["find_markdown_files"]["finds files in all directories (including hidden)"] = function()
	local workspace = helpers.create_temp_workspace({
		["visible/file.md"] = "# Visible",
		[".hidden/file.md"] = "# Hidden",
		["visible/.git/file.md"] = "# In git",
	})

	-- Save and override config
	local original_paths = config.refile_paths
	config.refile_paths = { workspace }

	local files = queries.find_markdown_files()

	-- Restore config
	config.refile_paths = original_paths

	-- Current implementation finds files in ALL directories (no hidden filtering)
	MiniTest.expect.equality(#files, 3)

	helpers.cleanup_temp(workspace)
end

T["find_markdown_files"]["handles permission errors gracefully"] = function()
	local workspace = helpers.create_temp_workspace({
		["accessible/file.md"] = "# File",
	})

	-- Create a directory without read permissions
	local forbidden = workspace .. "/forbidden"
	vim.fn.mkdir(forbidden, "p")
	vim.fn.writefile({ "# Forbidden" }, forbidden .. "/file.md")
	vim.fn.setfperm(forbidden, "---------")

	-- Save and override config
	local original_paths = config.refile_paths
	config.refile_paths = { workspace }

	-- Should not crash, just skip the forbidden directory
	local ok, files = pcall(queries.find_markdown_files)

	-- Restore config
	config.refile_paths = original_paths

	MiniTest.expect.equality(ok, true, "Should handle permission errors")
	MiniTest.expect.no_equality(#files, 0, "Should find at least one accessible file")

	-- Cleanup (restore permissions first)
	vim.fn.setfperm(forbidden, "rwxr-xr-x")
	helpers.cleanup_temp(workspace)
end

T["find_markdown_files - respects refile_heading_ignore patterns"] = function()
	-- Save original config
	local original_ignore = config.refile_heading_ignore
	local original_paths = config.refile_paths

	-- Create test directory structure
	local test_dir = "/tmp/org-markdown-test-ignore"
	vim.fn.mkdir(test_dir, "p")
	vim.fn.mkdir(test_dir .. "/archive", "p")

	-- Create test files
	local test_files = {
		test_dir .. "/notes.md",
		test_dir .. "/calendar.md",
		test_dir .. "/tasks.md",
		test_dir .. "/archive/old.md",
	}

	for _, file in ipairs(test_files) do
		vim.fn.writefile({ "# Test" }, file)
	end

	-- Test 1: No ignore patterns - should find all files
	config.refile_paths = { test_dir }
	config.refile_heading_ignore = {}
	local files = queries.find_markdown_files()
	MiniTest.expect.equality(#files, 4, "Should find all 4 markdown files")

	-- Test 2: Ignore exact filename
	config.refile_heading_ignore = { "calendar.md" }
	files = queries.find_markdown_files()
	MiniTest.expect.equality(#files, 3, "Should ignore calendar.md")
	for _, file in ipairs(files) do
		MiniTest.expect.no_equality(file:match("calendar%.md$"), "calendar.md", "Should not contain calendar.md")
	end

	-- Test 3: Ignore with wildcard pattern
	config.refile_heading_ignore = { "archive/*" }
	files = queries.find_markdown_files()
	MiniTest.expect.equality(#files, 3, "Should ignore archive directory")

	-- Test 4: Multiple ignore patterns
	config.refile_heading_ignore = { "calendar.md", "archive/*" }
	files = queries.find_markdown_files()
	MiniTest.expect.equality(#files, 2, "Should ignore calendar.md and archive/*")

	-- Cleanup
	vim.fn.delete(test_dir, "rf")
	config.refile_heading_ignore = original_ignore
	config.refile_paths = original_paths
end

return T
