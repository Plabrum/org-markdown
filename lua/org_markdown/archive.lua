local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local datetime = require("org_markdown.utils.datetime")
local queries = require("org_markdown.utils.queries")
local tree = require("org_markdown.utils.tree")
local document = require("org_markdown.utils.document")

local M = {}
local auto_archive_timer = nil

--- Check if archiving feature is enabled
--- @return boolean
function M.is_enabled()
	return config.archive and config.archive.enabled
end

--- Collect archivable nodes recursively from document tree
--- @param node table Document node
--- @param filepath string File path
--- @param today table Today's date
--- @param threshold_days number Days before archiving
--- @param archivable table Output array
local function collect_archivable_nodes(node, filepath, today, threshold_days, archivable)
	-- Check if this is a DONE heading
	if node:is_heading() and node:has_state("DONE") then
		-- Get completion date (from properties or legacy format)
		local completed_date = node:get_completed_at_date()
		if completed_date then
			-- Calculate days since completion
			local days_diff = datetime.days_between(completed_date, today)

			-- Archive if older than threshold
			if days_diff >= threshold_days then
				table.insert(archivable, {
					filepath = filepath,
					line_num = node.start_line,
					line = node.raw_heading,
					heading_level = node.level,
					completed_date = completed_date,
					days_old = days_diff,
				})
			end
		end
	end

	-- Recurse into children
	for _, child in ipairs(node.children or {}) do
		collect_archivable_nodes(child, filepath, today, threshold_days, archivable)
	end
end

--- Find all DONE headings older than threshold
--- @param threshold_days number Days before archiving
--- @return table Array of {filepath, line_num, line, heading_level}
function M.find_archivable_headings(threshold_days)
	local archivable = {}
	local today = datetime.today()
	local document = require("org_markdown.utils.document")

	-- Get all markdown files
	local files = queries.find_markdown_files()

	for _, filepath in ipairs(files) do
		-- Skip archive files
		if not filepath:match("%.archive%.md$") then
			local lines = utils.read_lines(filepath)
			if lines then
				-- Parse document into tree
				local root = document.parse(lines)

				-- Collect archivable nodes from tree
				collect_archivable_nodes(root, filepath, today, threshold_days, archivable)
			end
		end
	end

	return archivable
end

--- Get the full heading block including sub-headings
--- @param lines table Array of file lines
--- @param start_line number Starting line number (1-indexed)
--- @param heading_level number Level of the heading
--- @return number, number Start line, end line (1-indexed, inclusive)
local function get_heading_block(lines, start_line, heading_level)
	return tree.get_block(lines, start_line, heading_level)
end

--- Archive a single heading to archive file
--- @param filepath string Source file path
--- @param heading_info table Heading data from find_archivable_headings
--- @return boolean, string|nil Success, error message
function M.archive_heading(filepath, heading_info)
	-- Generate archive file path
	local archive_path = filepath:gsub("%.md$", config.archive.archive_suffix .. ".md")

	-- Read source file
	local lines = utils.read_lines(filepath)
	if not lines then
		return false, "Failed to read source file"
	end

	-- Get the full heading block (including sub-headings)
	local start_line, end_line = get_heading_block(lines, heading_info.line_num, heading_info.heading_level)

	-- Extract the heading block lines
	local block_lines = {}
	for i = start_line, end_line do
		table.insert(block_lines, lines[i])
	end

	-- Load or create archive document
	local archive_root
	if vim.fn.filereadable(archive_path) == 0 then
		-- Create new document with header
		archive_root = document.parse({
			"<!-- AUTO-ARCHIVED: Completed tasks moved from " .. vim.fn.fnamemodify(filepath, ":t") .. " -->",
			"",
		})
	else
		archive_root = document.read_from_file(archive_path)
	end

	-- Parse block lines and append to archive
	local block_root = document.parse(block_lines)

	-- Add blank line before archived content
	table.insert(archive_root.content_lines, "")

	-- Append headings and content
	for _, child in ipairs(block_root.children) do
		document.insert_child(archive_root, child)
	end
	for _, line in ipairs(block_root.content_lines) do
		table.insert(archive_root.content_lines, line)
	end

	-- Write archive file
	local ok, err = pcall(document.write_to_file, archive_path, archive_root)

	if not ok then
		return false, "Failed to write to archive: " .. tostring(err)
	end

	-- Verify the write succeeded by reading back
	local archive_lines = utils.read_lines(archive_path)
	if not archive_lines then
		return false, "Failed to verify archive write"
	end

	-- Store in register "r" for undo
	vim.fn.setreg("r", table.concat(block_lines, "\n"))

	-- Delete from source file using document model
	-- Parse source into tree
	local source_root = document.parse(lines)

	-- Find the node at the archived heading's line
	local node_to_remove = document.find_node_at_line(source_root, start_line)

	if node_to_remove and node_to_remove.type == "heading" then
		-- Find parent and remove the node
		local parent = document.find_parent(source_root, node_to_remove)
		if parent then
			document.remove_child(parent, node_to_remove)
		end
	end

	-- Serialize and write/apply
	local new_lines = document.serialize(source_root)

	-- Check if file is open in a buffer
	local bufnr = vim.fn.bufnr(filepath)
	if bufnr ~= -1 then
		-- File is open, apply minimal diff
		local changes = document.diff(lines, new_lines)
		document.apply_to_buffer(bufnr, changes)
	else
		-- File is closed, write directly
		utils.write_lines(filepath, new_lines)
	end

	return true, nil
end

--- Archive all eligible headings
--- @return table Stats {archived_count, error_count, files_processed, errors}
function M.archive_all_eligible()
	local threshold_days = config.archive.threshold_days or 30
	local archivable = M.find_archivable_headings(threshold_days)

	local stats = {
		archived_count = 0,
		error_count = 0,
		files_processed = {},
		errors = {},
	}

	-- Group by file for more efficient processing
	local by_file = {}
	for _, heading in ipairs(archivable) do
		if not by_file[heading.filepath] then
			by_file[heading.filepath] = {}
		end
		table.insert(by_file[heading.filepath], heading)
	end

	-- Process each file (sort headings in reverse order to avoid line number shifts)
	for filepath, headings in pairs(by_file) do
		-- Sort by line number descending (process bottom-up)
		table.sort(headings, function(a, b)
			return a.line_num > b.line_num
		end)

		for _, heading in ipairs(headings) do
			local success, err = M.archive_heading(filepath, heading)
			if success then
				stats.archived_count = stats.archived_count + 1
				stats.files_processed[filepath] = true
			else
				stats.error_count = stats.error_count + 1
				table.insert(stats.errors, {
					filepath = filepath,
					line_num = heading.line_num,
					error = err,
				})
			end
		end
	end

	-- Convert files_processed to count
	local file_count = 0
	for _ in pairs(stats.files_processed) do
		file_count = file_count + 1
	end

	-- Notify user
	vim.schedule(function()
		if stats.archived_count > 0 then
			vim.notify(
				string.format("Archived %d heading(s) from %d file(s)", stats.archived_count, file_count),
				vim.log.levels.INFO
			)
		elseif stats.error_count > 0 then
			vim.notify(string.format("Failed to archive %d heading(s)", stats.error_count), vim.log.levels.WARN)
		else
			vim.notify("No headings to archive", vim.log.levels.INFO)
		end
	end)

	return stats
end

--- Start auto-archive background timer
function M.start_auto_archive()
	if not M.is_enabled() then
		vim.notify("Archive feature is disabled", vim.log.levels.WARN)
		return
	end

	if not config.archive.auto_archive then
		vim.notify("Auto-archive is disabled in config", vim.log.levels.WARN)
		return
	end

	-- Stop existing timer if running
	M.stop_auto_archive()

	local interval = config.archive.interval or 86400000 -- 24 hours default

	-- Minimum interval validation (1 minute)
	if interval < 60000 then
		vim.notify("Auto-archive interval too short, using 1 minute", vim.log.levels.WARN)
		interval = 60000
	end

	auto_archive_timer = vim.loop.new_timer()
	auto_archive_timer:start(
		interval, -- Initial delay
		interval, -- Repeat interval
		vim.schedule_wrap(function()
			-- Prevent concurrent runs
			if M._is_archiving then
				return
			end

			M._is_archiving = true
			M.archive_all_eligible()
			M._is_archiving = false
		end)
	)

	vim.notify("Auto-archive started", vim.log.levels.INFO)
end

--- Stop auto-archive background timer
function M.stop_auto_archive()
	if auto_archive_timer then
		auto_archive_timer:stop()
		auto_archive_timer:close()
		auto_archive_timer = nil
	end
end

return M
