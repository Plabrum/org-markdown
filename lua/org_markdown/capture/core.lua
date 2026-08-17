--- Vim-free capture core: the pure template + document-mutation pieces shared by
--- the in-editor capture flow (capture.lua) and the standalone `org` CLI.
--- Nothing here touches async, buffers, keymaps or prompts. IO and path handling
--- route through `platform`, so the CLI entry points run under plain luajit while
--- the editor keeps its own IO (dir-creating writes) via document.write_to_file.

local parser = require("org_markdown.utils.parser")
local datetime = require("org_markdown.utils.datetime")
local document = require("org_markdown.utils.document")
local platform = require("org_markdown.platform")

local M = {}

-- Same marker character set capture.lua escapes before pattern matching.
local CAPTURE_TEMPLATE_CHARS = { "%", "^", "?", "<", ">" }

--- Substitute a template marker for a literal replacement.
--- The replacement is `%`-escaped so user content is inserted verbatim.
--- @param text string
--- @param marker string
--- @param replacement string
--- @return string
local function substitute(text, marker, replacement)
	local escaped_marker = parser.escape_marker(marker, CAPTURE_TEMPLATE_CHARS)
	local safe_replacement = (replacement or ""):gsub("%%", "%%%%")
	return (text:gsub(escaped_marker, safe_replacement))
end

--- Resolve the author name for the `%n` marker headlessly.
--- Prefers the caller-supplied value, then $USER, then a constant fallback.
--- @param author string|nil
--- @return string
local function resolve_author(author)
	if author and author ~= "" then
		return author
	end
	return os.getenv("USER") or "User"
end

--- Split a file's contents into lines, matching utils.read_lines' semantics
--- (newline-stripped, no trailing empty element for a final newline).
--- @param content string|nil
--- @return string[]
local function content_to_lines(content)
	local lines = {}
	if not content or content == "" then
		return lines
	end
	local pos = 1
	local len = #content
	while pos <= len do
		local nl = content:find("\n", pos, true)
		if nl then
			lines[#lines + 1] = content:sub(pos, nl - 1)
			pos = nl + 1
		else
			lines[#lines + 1] = content:sub(pos)
			pos = len + 1
		end
	end
	return lines
end

--- Join serialized lines back into file content (trailing newline like write_lines).
--- @param lines string[]
--- @return string
local function lines_to_content(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

--- Expand all non-interactive capture markers for headless use.
---
--- Interactive/editor-only markers are resolved without any UI:
---   %?          -> opts.content (the captured body; "" when absent)
---   %^{label}   -> "" (no prompting headless)
---   %f, %F, %a  -> opts.file (current-file markers map to the target file)
---   %x          -> "" (no clipboard headless)
---   %n          -> opts.author, else $USER, else "User"
--- Date markers (%t %T %u %U %H %Y %m %d %<fmt>) match the in-editor formats.
--- @param template string
--- @param opts table|nil { content?: string, file?: string, author?: string }
--- @return string
function M.expand_template(template, opts)
	opts = opts or {}
	local text = template
	local file = opts.file or ""

	-- Date/time markers (mirror capture.lua's key_mapping formats and order).
	text = substitute(text, "%T", datetime.capture_format("%Y-%m-%d %a %H:%M", "<"))
	text = substitute(text, "%t", datetime.capture_format("%Y-%m-%d %a", "<"))
	text = substitute(text, "%U", datetime.capture_format("%Y-%m-%d %a %H:%M", "["))
	text = substitute(text, "%u", datetime.capture_format("%Y-%m-%d %a", "["))
	text = substitute(text, "%n", resolve_author(opts.author))
	text = substitute(text, "%H", datetime.capture_format("%H:%M"))
	text = substitute(text, "%Y", datetime.capture_format("%Y"))
	text = substitute(text, "%m", datetime.capture_format("%m"))
	text = substitute(text, "%d", datetime.capture_format("%d"))

	-- Current-file markers: map to the target file (absolute path unavailable
	-- headless, so both %f and %F use the resolved file); %a has no line number.
	text = substitute(text, "%F", file)
	text = substitute(text, "%f", file)
	text = substitute(text, "%a", file)

	-- Custom date format: %<fmt>
	local custom = text:match(parser.escape_marker("%<.-%>", CAPTURE_TEMPLATE_CHARS))
	if custom then
		local fmt = custom:match("%<(.-)%>")
		if fmt then
			text = substitute(text, custom, datetime.capture_format(fmt))
		end
	end

	-- Clipboard and interactive prompt markers have no headless equivalent.
	text = substitute(text, "%x", "")
	text = text:gsub(parser.escape_marker("%^{", CAPTURE_TEMPLATE_CHARS) .. ".-}", "")

	-- Interactive body marker resolves to the supplied content.
	text = substitute(text, "%?", opts.content or "")

	return text
end

--- Insert captured content into an already-parsed document tree.
--- Shared by both capture entry points so the in-editor and CLI flows mutate
--- the tree identically; only the surrounding IO differs.
--- @param root Node Parsed destination document root
--- @param heading_text string|nil Heading text to insert under (nil/"" appends at end)
--- @param content_lines string[] Lines to insert
function M.insert_content(root, heading_text, content_lines)
	-- Parse captured content into nodes
	local captured_root = document.parse(content_lines)

	-- Determine where to insert
	local target_heading = nil
	if heading_text and heading_text ~= "" then
		target_heading = document.find_heading_by_text(root, heading_text)

		if not target_heading then
			-- Create new heading node if it doesn't exist
			target_heading = document.create_node({
				level = 1,
				text = heading_text,
			})
			document.insert_child(root, target_heading)
		end
	end

	if target_heading then
		-- Insert captured content as children of the target heading
		local base_level = target_heading.level

		-- Insert any headings from captured content with adjusted levels
		for _, child in ipairs(captured_root.children) do
			---@diagnostic disable-next-line: param-type-mismatch
			document.adjust_node_levels(child, base_level)
			document.insert_child(target_heading, child)
		end

		-- Add non-heading content to target's content_lines
		for _, line in ipairs(captured_root.content_lines) do
			table.insert(target_heading.content_lines, line)
		end
		target_heading.dirty = true
	else
		-- No heading specified - append to document root
		for _, child in ipairs(captured_root.children) do
			document.insert_child(root, child)
		end
		for _, line in ipairs(captured_root.content_lines) do
			table.insert(root.content_lines, line)
		end
	end
end

--- Standalone capture: read a file, insert content under a heading, write it back.
--- IO/path go through `platform` so this runs under the CLI with no Neovim.
--- Creates the file (and heading) when missing, mirroring the in-editor flow.
--- @param filepath string Path to the destination file
--- @param heading_text string|nil Heading text to insert under (nil/"" appends at end)
--- @param content_lines string[] Lines to insert
function M.insert_under_heading(filepath, heading_text, content_lines)
	local expanded = platform.path.expand(filepath)

	-- Read and parse destination file (absent file starts an empty document).
	local existing = platform.fs.read_file(expanded)
	local root = document.parse(content_to_lines(existing))

	M.insert_content(root, heading_text, content_lines)

	local serialized = document.serialize(root)
	return platform.fs.write_file(expanded, lines_to_content(serialized))
end

return M
