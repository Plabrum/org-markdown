local M = {}

--- Parses an org heading line and extracts state, priority, text, and tags.
---
--- Expected format: `# STATE [#P] text :tag1:tag2:`
---
--- @param line string The line to parse (e.g., "# TODO [#A] Finish task :urgent:")
--- @return table|nil state The task state ("TODO" or "IN_PROGRESS"), or nil if invalid
--- @return string|nil priority The priority (e.g., "#A"), or nil if not present
--- @return string|nil text The main heading text without tags or status, or nil if not matched
--- @return string[] tags A list of tag strings (e.g., {"urgent", "work"})
function M.parse_heading(line)
	local state, priority, text = line:match("^#+%s+(%u+)%s+(%[%#%u%])?%s*(.-)%s*$")
	if not state or (state ~= "TODO" and state ~= "IN_PROGRESS") then
		return nil
	end
	local tags = {}
	for tag in line:gmatch(":([%w_-]+):") do
		table.insert(tags, tag)
	end
	local pri = priority and priority:match("%[(#%u)%]") or nil
	return state, pri, text, tags
end

function M.extract_date(line)
	local tracked = line:match("<(%d%d%d%d%-%d%d%-%d%d)>")
	local untracked = line:match("%[(%d%d%d%d%-%d%d%-%d%d)%]")
	return tracked, untracked
end

function M.escaped_substitute(s, marker, repl, opts)
	opts = opts or {}
	local escape_chars, count = opts.escape_chars or {}, opts.count or nil
	-- Build a pattern to match any of the specified characters
	if escape_chars and #escape_chars > 0 then
		-- Escape characters that are special in Lua patterns for use in class
		local escaped = {}
		for _, char in ipairs(escape_chars) do
			local c = char:gsub("([^%w])", "%%%1") -- escape for pattern class
			table.insert(escaped, c)
		end
		local pattern_class = "[" .. table.concat(escaped) .. "]"
		marker = marker:gsub(pattern_class, function(c)
			return "%" .. c
		end)
	end

	return s:gsub(marker, repl, count)
end

--- Capture templates ---
--- Iterates through an input string and replaces any keys in key_mapping
--- with the result of their mapping function or static string, can use a custom substitution function.
---
function M.substitute_dynamic_values(template, key_mapping, custom_substitutor)
	local substitutor = custom_substitutor or function(s, m, r)
		s:gsub(m, r)
	end
	for key, fn_or_str in pairs(key_mapping) do
		local replacement_fn = function()
			if type(fn_or_str) == "function" then
				local ok, result = pcall(fn_or_str, key)
				return ok and (result or "") or ""
			end
			return fn_or_str
		end
		-- 	template =
		-- 		M.escaped_substitute(template, key, replacement_fn, { count = 1, escape_chars = M.CAPTURE_TEMPLATE_CHARS })
		template = substitutor(template, key, replacement_fn)
	end
	return template
end

--- Finds a target marker in a multiline string, removes it,
--- and returns the cleaned string and cursor coordinates if found.
--- @param input string: The multiline string to search
--- @param marker string: The exact substring to find and remove (e.g., "%%?" for %?)
--- @param custom_substitutor? fun(s: string, m: string, r: string): string Optional custom substitution function
--- @return string, integer|nil, integer|nil: cleaned string, row (0-based), column (0-based) or nil if not found
function M.strip_marker_and_get_position(input, marker, custom_substitutor)
	local substitutor = custom_substitutor or function(s, m, r)
		return s:gsub(m, r)
	end

	local lines = vim.split(input, "\n")
	local cursor_row, cursor_col = nil, nil

	for i, line in ipairs(lines) do
		local col = line:find(marker, 1, true) -- plain match
		if col and not cursor_row then
			cursor_row = i - 1
			cursor_col = col - 1
			line = substitutor(line, marker, "")
			-- line = M.escaped_substitute(line, marker, "", { count = 1, escape_chars = M.CAPTURE_TEMPLATE_CHARS })
		end
		lines[i] = line
	end

	return table.concat(lines, "\n"), cursor_row, cursor_col
end

return M
