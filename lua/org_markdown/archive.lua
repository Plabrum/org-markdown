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

--- Whether a heading node is DONE and completed at least threshold_days ago
--- @param node table Document node
--- @param today table Today's date
--- @param threshold_days number Days before archiving
---@diagnostic disable-next-line: undefined-doc-name
--- @return boolean, table|nil eligible, completed_date
local function is_done_and_old(node, today, threshold_days)
	if not (node:is_heading() and node:has_state("DONE")) then
		---@diagnostic disable-next-line: missing-return-value
		return false, nil
	end
	local completed_date = node:get_completed_at_date()
	if not completed_date then
		---@diagnostic disable-next-line: missing-return-value
		return false, nil
	end
	---@diagnostic disable-next-line: missing-return-value
	return datetime.days_between(completed_date, today) >= threshold_days, completed_date
end

--- Whether any descendant heading is still incomplete (not DONE).
--- Used to keep blocks with open subtasks in place instead of archiving them.
--- @param node table Document node
--- @return boolean
local function has_incomplete_descendant(node)
	for _, child in ipairs(node.children or {}) do
		if child:is_heading() and not child:has_state("DONE") then
			return true
		end
		if has_incomplete_descendant(child) then
			return true
		end
	end
	return false
end

--- Collect archivable nodes recursively from document tree
--- @param node table Document node
--- @param filepath string File path
--- @param today table Today's date
--- @param threshold_days number Days before archiving
--- @param archivable table Output array
local function collect_archivable_nodes(node, filepath, today, threshold_days, archivable)
	-- Archive a heading as a whole block only when it is DONE + old AND every
	-- descendant is also complete. If any descendant is still incomplete, leave
	-- the block in place so open subtasks are never swept into the archive.
	local eligible, completed_date = is_done_and_old(node, today, threshold_days)
	if eligible and not has_incomplete_descendant(node) then
		---@diagnostic disable-next-line: param-type-mismatch
		local days_diff = datetime.days_between(completed_date, today)
		table.insert(archivable, {
			filepath = filepath,
			line_num = node.start_line,
			line = node.raw_heading,
			heading_level = node.level,
			completed_date = completed_date,
			days_old = days_diff,
		})
		-- Don't recurse: the whole subtree moves with this block.
		return
	end

	-- Not archived as a block; recurse to find eligible nested blocks.
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
				---@diagnostic disable-next-line: param-type-mismatch
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
---@diagnostic disable-next-line: undefined-doc-name
--- @return boolean, string|nil Success, error message
function M.archive_heading(filepath, heading_info)
	-- Generate archive file path
	local archive_path = filepath:gsub("%.md$", config.archive.archive_suffix .. ".md")

	-- Read source file
	local lines = utils.read_lines(filepath)
	if not lines then
		---@diagnostic disable-next-line: missing-return-value
		return false, "Failed to read source file"
	end

	-- Get the full heading block (including sub-headings)
	local start_line, end_line = get_heading_block(lines, heading_info.line_num, heading_info.heading_level)

	-- Extract the heading block lines
	local block_lines = {}
	for i = start_line, end_line do
		table.insert(block_lines, lines[i])
	end

	-- Load or create the archive file's existing lines.
	-- We append the block as raw text rather than round-tripping it through the
	-- document tree: serialize emits all root content_lines before any children,
	-- so appending separators/content via the tree would pile them at the top of
	-- the file instead of placing them between archived blocks.
	local archive_lines_out
	if vim.fn.filereadable(archive_path) == 0 then
		archive_lines_out = {
			"<!-- AUTO-ARCHIVED: Completed tasks moved from " .. vim.fn.fnamemodify(filepath, ":t") .. " -->",
		}
	else
		archive_lines_out = utils.read_lines(archive_path) or {}
	end

	-- Ensure a single blank-line separator before the appended block.
	if #archive_lines_out > 0 and archive_lines_out[#archive_lines_out] ~= "" then
		table.insert(archive_lines_out, "")
	end

	-- Append the archived block verbatim (preserves original property/content order).
	for _, line in ipairs(block_lines) do
		table.insert(archive_lines_out, line)
	end

	-- Write archive file
	local ok, err = pcall(utils.write_lines, archive_path, archive_lines_out)

	if not ok then
		---@diagnostic disable-next-line: missing-return-value
		return false, "Failed to write to archive: " .. tostring(err)
	end

	-- Verify the write succeeded by reading back
	local archive_lines = utils.read_lines(archive_path)
	if not archive_lines then
		---@diagnostic disable-next-line: missing-return-value
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

	---@diagnostic disable-next-line: missing-return-value
	return true, nil
end

--- Archive all eligible headings
--- @param opts table|nil Options: { silent_when_empty = boolean } to suppress the
---   "No headings to archive" notification when nothing was archived (used by the
---   auto-archive timer so empty sweeps stay quiet)
--- @return table Stats {archived_count, error_count, files_processed, errors}
function M.archive_all_eligible(opts)
	opts = opts or {}
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
		elseif not opts.silent_when_empty then
			vim.notify("No headings to archive", vim.log.levels.INFO)
		end
	end)

	return stats
end

--- Start auto-archive background timer
--- @param opts table|nil Options: { silent = boolean } to suppress the
---   "Auto-archive started" notification (used when auto-starting on Neovim startup)
function M.start_auto_archive(opts)
	opts = opts or {}
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

	-- Run the first sweep shortly after startup (not a full interval later), so
	-- restarting Neovim regularly doesn't perpetually defer archiving.
	local initial_delay = config.archive.initial_delay or 5000

	auto_archive_timer = vim.loop.new_timer()
	auto_archive_timer:start(
		initial_delay, -- Initial delay
		interval, -- Repeat interval
		vim.schedule_wrap(function()
			-- Prevent concurrent runs
			if M._is_archiving then
				return
			end

			M._is_archiving = true
			-- Empty sweeps stay quiet; only real work (archived/errors) notifies
			M.archive_all_eligible({ silent_when_empty = true })
			M._is_archiving = false
		end)
	)

	if not opts.silent then
		vim.notify("Auto-archive started", vim.log.levels.INFO)
	end
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
