local config = require("org_markdown.config")
local utils = require("org_markdown.utils.utils")
local parser = require("org_markdown.utils.parser")
local datetime = require("org_markdown.utils.datetime")
local queries = require("org_markdown.utils.queries")
local tree = require("org_markdown.utils.tree")

local M = {}
local auto_archive_timer = nil

--- Check if archiving feature is enabled
--- @return boolean
function M.is_enabled()
	return config.archive and config.archive.enabled
end

--- Add COMPLETED_AT timestamp to a heading line
--- @param line string The heading line
--- @return string Modified line with timestamp
function M.add_completed_timestamp(line)
	-- Check if line already has COMPLETED_AT timestamp
	if line:match("COMPLETED_AT:") then
		return line
	end

	-- Get today's date
	local today = datetime.today()
	local date_str = datetime.to_iso_string(today)

	-- Parse the heading to extract components
	local parsed = parser.parse_headline(line)
	if not parsed then
		return line
	end

	-- Extract the heading prefix (## or ### etc) and state
	local hashes, state = line:match("^(#+)%s+(%u[%u_%-]*)")
	if not (hashes and state) then
		return line
	end

	-- Build the new line by inserting COMPLETED_AT before tags
	local parts = {}
	table.insert(parts, hashes)
	table.insert(parts, state)

	-- Add priority if present
	if parsed.priority then
		table.insert(parts, string.format("[#%s]", parsed.priority))
	end

	-- Add text
	if parsed.text and parsed.text ~= "" then
		table.insert(parts, parsed.text)
	end

	-- Add tracked date if present
	if parsed.tracked then
		table.insert(parts, string.format("<%s>", parsed.tracked))
	end

	-- Add untracked date if present
	if parsed.untracked then
		table.insert(parts, string.format("[%s]", parsed.untracked))
	end

	-- Add COMPLETED_AT timestamp
	table.insert(parts, string.format("COMPLETED_AT: [%s]", date_str))

	-- Add tags if present
	if parsed.tags and #parsed.tags > 0 then
		table.insert(parts, ":" .. table.concat(parsed.tags, ":") .. ":")
	end

	return table.concat(parts, " ")
end

--- Extract COMPLETED_AT date from heading line
--- @param line string The heading line
--- @return table|nil Date table {year, month, day} or nil
function M.extract_completed_date(line)
	local date_str = line:match("COMPLETED_AT: %[(%d%d%d%d%-%d%d%-%d%d)%]")
	if not date_str then
		return nil
	end

	-- Parse ISO date string YYYY-MM-DD
	local year, month, day = date_str:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if not (year and month and day) then
		return nil
	end

	return {
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
	}
end

--- Find all DONE headings older than threshold
--- @param threshold_days number Days before archiving
--- @return table Array of {filepath, line_num, line, heading_level}
function M.find_archivable_headings(threshold_days)
	local archivable = {}
	local today = datetime.today()

	-- Get all markdown files
	local files = queries.find_markdown_files()

	for _, filepath in ipairs(files) do
		-- Skip archive files
		if not filepath:match("%.archive%.md$") then
			local lines = utils.read_lines(filepath)
			if lines then
				for line_num, line in ipairs(lines) do
					-- Check if it's a heading with DONE state
					local parsed = parser.parse_headline(line)
					if parsed and parsed.state == "DONE" then
						-- Extract completion date
						local completed_date = M.extract_completed_date(line)
						if completed_date then
							-- Calculate days since completion
							local days_diff = datetime.days_between(completed_date, today)

							-- Archive if older than threshold
							if days_diff >= threshold_days then
								-- Get heading level
								local heading_level = tree.get_level(line) or 2

								table.insert(archivable, {
									filepath = filepath,
									line_num = line_num,
									line = line,
									heading_level = heading_level,
									completed_date = completed_date,
									days_old = days_diff,
								})
							end
						end
					end
				end
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

	-- Create archive file if it doesn't exist
	if vim.fn.filereadable(archive_path) == 0 then
		local header_lines = {
			"<!-- AUTO-ARCHIVED: Completed tasks moved from " .. vim.fn.fnamemodify(filepath, ":t") .. " -->",
			"",
		}
		utils.write_lines(archive_path, header_lines)
	end

	-- Append to archive file
	local ok, err = pcall(function()
		-- Add a blank line before the archived heading for readability
		utils.append_lines(archive_path, { "" })
		utils.append_lines(archive_path, block_lines)
	end)

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

	-- Delete from source file
	-- Check if file is open in a buffer
	local bufnr = vim.fn.bufnr(filepath)
	if bufnr ~= -1 then
		-- File is open, use buffer API
		vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, {})
	else
		-- File is closed, manipulate directly
		local new_lines = {}
		for i, line in ipairs(lines) do
			if i < start_line or i > end_line then
				table.insert(new_lines, line)
			end
		end
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
