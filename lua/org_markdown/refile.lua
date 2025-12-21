local utils = require("org_markdown.utils.utils")
local queries = require("org_markdown.utils.queries")
local config = require("org_markdown.config")
local picker = require("org_markdown.utils.picker")
local async = require("org_markdown.utils.async")
local frontmatter = require("org_markdown.utils.frontmatter")
local tree = require("org_markdown.utils.tree")

local M = {}

--- Verify that refiled content was successfully written to destination
--- @param filepath string Path to destination file
--- @param expected_lines table Lines that should have been written
--- @return boolean, string Success status and error message if failed
local function verify_refile_write(filepath, expected_lines)
	local expanded = vim.fn.expand(filepath)

	-- Check file is readable
	if vim.fn.filereadable(expanded) == 0 then
		return false, "Destination file not readable after write"
	end

	local written = utils.read_lines(expanded)

	-- Check last N lines match what we wrote
	local verify_count = math.min(5, #expected_lines)
	local start_idx = #written - verify_count + 1

	-- Handle case where file has fewer lines than expected
	if start_idx < 1 then
		return false, string.format("Destination file has %d lines but expected at least %d", #written, #expected_lines)
	end

	for i = 1, verify_count do
		local expected = expected_lines[i]
		local actual = written[start_idx + i - 1]

		if actual ~= expected then
			return false, string.format("Content mismatch at line %d: expected '%s', got '%s'", i, expected, actual or "nil")
		end
	end

	return true, nil
end

function M.get_refile_target()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] -- Keep 1-indexed for lines array access
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local current = lines[row]

	if not current then
		vim.notify("No content at cursor position", vim.log.levels.ERROR)
		return nil
	end

	current = current:match("^%s*(.*)")
	-- 1. Bullet match
	if current:match("^%s*[-*+] %[[ x%-]%]") or current:match("^%s*[-*+] ") then
		return {
			lines = { current },
			start_line = row - 1, -- Convert to 0-indexed for nvim_buf_set_lines
			end_line = row,
		}
	end

	-- 2. Heading match
	local level = tree.get_level(current)
	if level then
		local block_lines = tree.extract_block(lines, row, level)
		return {
			lines = block_lines,
			start_line = row - 1, -- Convert to 0-indexed for nvim_buf_set_lines
			end_line = row + #block_lines - 1,
		}
	end

	vim.notify("No bullet or heading detected to refile", vim.log.levels.ERROR)
	return nil
end

function M.to_file()
	-- 1. Try to resolve content under cursor first
	local selection = M.get_refile_target()
	if not selection or not selection.lines then
		vim.notify("No bullet point or heading detected to refile", vim.log.levels.ERROR)
		return
	end
	-- 2. Ask user to pick destination file
	local files = queries.find_markdown_files()

	local items = vim.tbl_map(function(file)
		local display_name = frontmatter.get_display_name(file)
		return { value = file, file = file, name = display_name }
	end, files)

	picker.pick(items, {
		prompt = "Refile to file:",
		kind = "files",
		format_item = function(item)
			-- Show display name (from frontmatter or filename) with path as secondary info
			local path_hint = vim.fn.fnamemodify(item.value, ":~:.:h")
			if path_hint == "." then
				return { { item.name, "Directory" } }
			else
				return {
					{ item.name, "Directory" },
					{ " (" .. path_hint .. ")", "Comment" },
				}
			end
		end,
		on_confirm = function(item)
			-- TRANSACTION ORDER: write → verify → delete
			-- This prevents data loss if write fails

			-- 1. Write to destination FIRST
			local write_ok, write_err = pcall(utils.append_lines, item.value, selection.lines)
			if not write_ok then
				vim.notify("Refile failed: " .. tostring(write_err), vim.log.levels.ERROR)
				return -- Source untouched!
			end

			-- 2. Verify write succeeded
			local verify_ok, verify_err = verify_refile_write(item.value, selection.lines)
			if not verify_ok then
				vim.notify("Refile verification failed: " .. verify_err, vim.log.levels.ERROR)
				return -- Source still untouched
			end

			-- 3. Store in register for undo (before delete!)
			vim.fn.setreg("r", table.concat(selection.lines, "\n"))

			-- 4. NOW safe to delete from source
			vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})

			vim.notify("Refiled to " .. item.value .. ' (undo: press "rp in target file)')
		end,
	})
end

function M.to_heading()
	-- 1. Get content to refile
	local selection = M.get_refile_target()
	if not selection or not selection.lines then
		vim.notify("No bullet point or heading detected to refile", vim.log.levels.ERROR)
		return
	end

	-- 2. Get all headings using shared utility
	local all_headings = utils.get_all_headings()

	if #all_headings == 0 then
		vim.notify("No headings found in any markdown files", vim.log.levels.WARN)
		return
	end

	-- 3. Show single picker with all headings
	picker.pick(all_headings, {
		prompt = "Refile under heading:",
		kind = "generic",
		format_item = function(item)
			-- Show as: "  Heading Name  (filename)"
			return {
				{ item.display, "Directory" },
				{ "  (" .. item.filename .. ")", "Comment" },
			}
		end,
		on_confirm = function(item)
			-- 4. Insert under heading (this also writes the file)
			utils.insert_under_heading(item.filepath, item.heading_text, selection.lines)

			-- 5. Store in register for undo
			vim.fn.setreg("r", table.concat(selection.lines, "\n"))

			-- 6. Delete from source
			vim.api.nvim_buf_set_lines(0, selection.start_line, selection.end_line, false, {})

			vim.notify("Refiled to " .. item.filename .. " → " .. item.heading_text .. ' (undo: press "rp in target file)')
		end,
	})
end

return M
