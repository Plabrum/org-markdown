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

return T
