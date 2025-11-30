local M = {}

-- Helper: Build tags string
local function build_tags_str(tags)
	if not tags or #tags == 0 then
		return ""
	end
	return " :" .. table.concat(tags, ":") .. ":"
end

-- Helper: Wrap text to fit in box width
local function wrap_text(text, max_width)
	local lines = {}
	local remaining = text

	while #remaining > 0 do
		if #remaining <= max_width then
			table.insert(lines, remaining)
			break
		else
			-- Find best break point
			local break_at = max_width
			for i = break_at, 1, -1 do
				if remaining:sub(i, i):match("%s") then
					break_at = i
					break
				end
			end
			table.insert(lines, vim.trim(remaining:sub(1, break_at)))
			remaining = vim.trim(remaining:sub(break_at + 1))
		end
	end

	return lines
end

-- Format all-day event in blocks style
local function format_blocks_all_day(item, indent)
	local tags_str = build_tags_str(item.tags)
	return indent .. "▓▓ " .. item.title .. " (all-day)" .. tags_str
end

-- Format time range event in blocks style
local function format_blocks_time_range(item, indent, box_width)
	local title_with_tags = item.title .. build_tags_str(item.tags)
	local lines = wrap_text(title_with_tags, box_width - 4)

	local result = {}
	table.insert(result, string.format("%s┌─ %s %s┐", indent, item.start_time, string.rep("─", box_width - 9)))

	for _, line in ipairs(lines) do
		table.insert(result, string.format("%s│ %-" .. (box_width - 2) .. "s │", indent, line))
	end

	table.insert(result, string.format("%s└%s %s ─┘", indent, string.rep("─", box_width - 9), item.end_time))

	return table.concat(result, "\n")
end

-- Format simple time event in blocks style
local function format_blocks_simple_time(item, indent)
	local tags_str = build_tags_str(item.tags)
	return indent .. item.start_time .. "  " .. item.title .. tags_str
end

-- Format simple event (no time) in blocks style
local function format_blocks_simple(item, indent)
	local tags_str = build_tags_str(item.tags)
	return indent .. item.title .. tags_str
end

-- Format item in blocks style
function M.format_blocks(item, indent)
	indent = indent or ""
	local box_width = 50

	if item.all_day then
		return format_blocks_all_day(item, indent)
	elseif item.start_time and item.end_time then
		return format_blocks_time_range(item, indent, box_width)
	elseif item.start_time then
		return format_blocks_simple_time(item, indent)
	else
		return format_blocks_simple(item, indent)
	end
end

-- Format item in timeline style
function M.format_timeline(item, indent)
	indent = indent or ""
	local parts = {}

	if item.state then
		-- Task format: STATE [priority] title (time) :tags:
		table.insert(parts, item.state)
		if item.priority then
			table.insert(parts, string.format("[%s]", item.priority))
		end
		table.insert(parts, item.title)

		-- Add time inline if exists
		if item.start_time then
			local time_str = item.end_time and string.format("(%s-%s)", item.start_time, item.end_time)
				or string.format("(%s)", item.start_time)
			table.insert(parts, time_str)
		end
	else
		-- Calendar format: time title :tags:
		if item.all_day then
			table.insert(parts, "[ALL-DAY]")
		elseif item.start_time then
			local time_str = item.end_time and item.start_time .. "-" .. item.end_time or item.start_time
			table.insert(parts, time_str)
		end
		table.insert(parts, item.title)
	end

	local tags_str = build_tags_str(item.tags)
	return indent .. table.concat(parts, " ") .. tags_str
end

-- Main formatting entry point
function M.format_item(item, opts)
	opts = opts or {}

	local indent = opts.indent or ""
	local style = opts.style or "blocks"

	if style == "blocks" then
		return M.format_blocks(item, indent)
	elseif style == "timeline" then
		return M.format_timeline(item, indent)
	else
		error("Unknown formatter style: " .. style)
	end
end

-- Export styles for reference
M.styles = {
	blocks = { box_width = 50 },
	timeline = {},
}

return M
