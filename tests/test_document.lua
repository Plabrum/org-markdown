local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local document = require("org_markdown.utils.document")

-- ============================================================================
-- Parse Tests
-- ============================================================================

T["parse - creates document node for empty file"] = function()
	local lines = {}
	local root = document.parse(lines)
	MiniTest.expect.equality(root.type, "document")
	MiniTest.expect.equality(#root.children, 0)
end

T["parse - parses single heading"] = function()
	local lines = {
		"## TODO Task",
	}
	local root = document.parse(lines)
	MiniTest.expect.equality(#root.children, 1)
	MiniTest.expect.equality(root.children[1].type, "heading")
	MiniTest.expect.equality(root.children[1].level, 2)
	MiniTest.expect.equality(root.children[1].parsed.state, "TODO")
	MiniTest.expect.equality(root.children[1].parsed.text, "Task")
end

T["parse - parses heading with content"] = function()
	local lines = {
		"## TODO Task",
		"Some content here",
		"More content",
	}
	local root = document.parse(lines)
	MiniTest.expect.equality(#root.children, 1)
	local node = root.children[1]
	MiniTest.expect.equality(#node.content_lines, 2)
	MiniTest.expect.equality(node.content_lines[1], "Some content here")
	MiniTest.expect.equality(node.content_lines[2], "More content")
end

T["parse - parses nested headings"] = function()
	local lines = {
		"## Parent",
		"### Child",
		"Content",
	}
	local root = document.parse(lines)
	MiniTest.expect.equality(#root.children, 1)
	local parent = root.children[1]
	MiniTest.expect.equality(#parent.children, 1)
	MiniTest.expect.equality(parent.children[1].level, 3)
end

T["parse - extracts properties from content"] = function()
	local lines = {
		"## DONE Task",
		"Some content",
		"COMPLETED_AT: [2025-12-22]",
	}
	local root = document.parse(lines)
	local node = root.children[1]
	MiniTest.expect.equality(node.properties.COMPLETED_AT, "2025-12-22")
	MiniTest.expect.equality(#node.content_lines, 1)
	MiniTest.expect.equality(node.content_lines[1], "Some content")
end

T["parse - handles document content before first heading"] = function()
	local lines = {
		"Document intro",
		"",
		"## First heading",
	}
	local root = document.parse(lines)
	MiniTest.expect.equality(#root.content_lines, 2)
	MiniTest.expect.equality(root.content_lines[1], "Document intro")
	MiniTest.expect.equality(#root.children, 1)
end

T["parse - tracks line numbers"] = function()
	local lines = {
		"## Heading 1",
		"Content",
		"## Heading 2",
	}
	local root = document.parse(lines)
	MiniTest.expect.equality(root.children[1].start_line, 1)
	MiniTest.expect.equality(root.children[1].end_line, 2)
	MiniTest.expect.equality(root.children[2].start_line, 3)
	MiniTest.expect.equality(root.children[2].end_line, 3)
end

T["parse - parses complex heading"] = function()
	local lines = {
		"## TODO [#A] Buy groceries <2025-12-22> :shopping:work:",
	}
	local root = document.parse(lines)
	local node = root.children[1]
	MiniTest.expect.equality(node.parsed.state, "TODO")
	MiniTest.expect.equality(node.parsed.priority, "A")
	MiniTest.expect.equality(node.parsed.tracked, "2025-12-22")
	MiniTest.expect.equality(node.parsed.text, "Buy groceries")
	MiniTest.expect.equality(#node.parsed.tags, 2)
end

-- ============================================================================
-- Serialize Tests
-- ============================================================================

T["serialize - round trips simple document"] = function()
	local lines = {
		"## TODO Task",
		"Content",
	}
	local root = document.parse(lines)
	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], lines[1])
	MiniTest.expect.equality(output[2], lines[2])
end

T["serialize - round trips nested structure"] = function()
	local lines = {
		"## Parent",
		"Parent content",
		"### Child",
		"Child content",
	}
	local root = document.parse(lines)
	local output = document.serialize(root)
	for i, line in ipairs(lines) do
		MiniTest.expect.equality(output[i], line)
	end
end

T["serialize - includes properties at end of content"] = function()
	local lines = {
		"## DONE Task",
		"Content",
	}
	local root = document.parse(lines)
	root.children[1].properties.COMPLETED_AT = "2025-12-22"
	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## DONE Task")
	MiniTest.expect.equality(output[2], "Content")
	MiniTest.expect.equality(output[3], "COMPLETED_AT: [2025-12-22]")
end

T["serialize - reconstructs dirty heading"] = function()
	local lines = {
		"## TODO Task",
	}
	local root = document.parse(lines)
	root.children[1].parsed.state = "DONE"
	root.children[1].dirty = true
	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## DONE Task")
end

T["serialize - preserves document content"] = function()
	local lines = {
		"Intro text",
		"## Heading",
	}
	local root = document.parse(lines)
	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "Intro text")
	MiniTest.expect.equality(output[2], "## Heading")
end

-- ============================================================================
-- Diff Tests
-- ============================================================================

T["diff - returns empty for identical lines"] = function()
	local lines = { "line 1", "line 2" }
	local changes = document.diff(lines, lines)
	MiniTest.expect.equality(#changes, 0)
end

T["diff - detects single line change"] = function()
	local original = { "## TODO Task" }
	local modified = { "## DONE Task" }
	local changes = document.diff(original, modified)
	MiniTest.expect.equality(#changes, 1)
	MiniTest.expect.equality(changes[1].op, "replace")
	MiniTest.expect.equality(changes[1].line, 1)
end

T["diff - detects insertion"] = function()
	local original = { "line 1", "line 2" }
	local modified = { "line 1", "inserted", "line 2" }
	local changes = document.diff(original, modified)
	MiniTest.expect.equality(#changes, 1)
	MiniTest.expect.equality(changes[1].op, "insert")
end

T["diff - detects deletion"] = function()
	local original = { "line 1", "to delete", "line 2" }
	local modified = { "line 1", "line 2" }
	local changes = document.diff(original, modified)
	MiniTest.expect.equality(#changes, 1)
	MiniTest.expect.equality(changes[1].op, "delete")
end

-- ============================================================================
-- find_node_at_line Tests
-- ============================================================================

T["find_node_at_line - finds heading at line"] = function()
	local lines = {
		"## First",
		"Content",
		"## Second",
	}
	local root = document.parse(lines)
	local node = document.find_node_at_line(root, 1)
	MiniTest.expect.equality(node.raw_heading, "## First")
end

T["find_node_at_line - finds heading for content line"] = function()
	local lines = {
		"## Heading",
		"Content line",
	}
	local root = document.parse(lines)
	local node = document.find_node_at_line(root, 2)
	MiniTest.expect.equality(node.raw_heading, "## Heading")
end

T["find_node_at_line - returns nil for out of range"] = function()
	local lines = { "## Heading" }
	local root = document.parse(lines)
	local node = document.find_node_at_line(root, 100)
	MiniTest.expect.equality(node, nil)
end

-- ============================================================================
-- set_state Tests
-- ============================================================================

T["set_state - changes state"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	local node = root.children[1]
	node:set_state("DONE")
	MiniTest.expect.equality(node.parsed.state, "DONE")
	MiniTest.expect.equality(node.dirty, true)
end

T["set_state - removes COMPLETED_AT when leaving DONE"] = function()
	local lines = { "## DONE Task", "COMPLETED_AT: [2025-12-22]" }
	local root = document.parse(lines)
	local node = root.children[1]
	node:set_state("TODO")
	MiniTest.expect.equality(node.properties.COMPLETED_AT, nil)
end

-- ============================================================================
-- Property Tests
-- ============================================================================

T["set_property - sets property"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	local node = root.children[1]
	node:set_property("CUSTOM", "value")
	MiniTest.expect.equality(node.properties.CUSTOM, "value")
end

T["get_property - returns property value"] = function()
	local lines = { "## DONE Task", "CUSTOM: [myvalue]" }
	local root = document.parse(lines)
	local node = root.children[1]
	MiniTest.expect.equality(node:get_property("CUSTOM"), "myvalue")
end

T["get_property - returns nil for missing property"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	local node = root.children[1]
	MiniTest.expect.equality(node:get_property("MISSING"), nil)
end

-- ============================================================================
-- Node Method Tests
-- ============================================================================

T["is_heading - returns true for heading node"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	MiniTest.expect.equality(root.children[1]:is_heading(), true)
end

T["is_heading - returns false for document node"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	MiniTest.expect.equality(root:is_heading(), false)
end

T["has_state - returns true when state matches"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	MiniTest.expect.equality(root.children[1]:has_state("TODO"), true)
end

T["has_state - returns false when state differs"] = function()
	local lines = { "## TODO Task" }
	local root = document.parse(lines)
	MiniTest.expect.equality(root.children[1]:has_state("DONE"), false)
end

T["get_completed_at - returns date from properties"] = function()
	local lines = { "## DONE Task", "COMPLETED_AT: [2025-12-22]" }
	local root = document.parse(lines)
	MiniTest.expect.equality(root.children[1]:get_completed_at(), "2025-12-22")
end

T["get_completed_at_date - returns date table"] = function()
	local lines = { "## DONE Task", "COMPLETED_AT: [2025-12-22]" }
	local root = document.parse(lines)
	local date = root.children[1]:get_completed_at_date()
	MiniTest.expect.equality(date.year, 2025)
	MiniTest.expect.equality(date.month, 12)
	MiniTest.expect.equality(date.day, 22)
end

-- ============================================================================
-- Integration Tests
-- ============================================================================

T["integration - cycle to DONE adds COMPLETED_AT at content end"] = function()
	local lines = {
		"## TODO Task",
		"Some content",
		"## Next heading",
	}
	local root = document.parse(lines)
	local node = root.children[1]

	-- Simulate cycling to DONE (without archive check)
	node.parsed.state = "DONE"
	node.dirty = true
	node.properties.COMPLETED_AT = "2025-12-22"

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## DONE Task")
	MiniTest.expect.equality(output[2], "Some content")
	MiniTest.expect.equality(output[3], "COMPLETED_AT: [2025-12-22]")
	MiniTest.expect.equality(output[4], "## Next heading")
end

T["integration - nested heading preserves structure"] = function()
	local lines = {
		"## TODO Parent",
		"Parent content",
		"### Child",
		"Child content",
		"## Sibling",
	}
	local root = document.parse(lines)

	-- Cycle parent to DONE
	local parent = root.children[1]
	parent.parsed.state = "DONE"
	parent.dirty = true
	parent.properties.COMPLETED_AT = "2025-12-22"

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## DONE Parent")
	MiniTest.expect.equality(output[2], "Parent content")
	MiniTest.expect.equality(output[3], "COMPLETED_AT: [2025-12-22]")
	MiniTest.expect.equality(output[4], "### Child")
	MiniTest.expect.equality(output[5], "Child content")
	MiniTest.expect.equality(output[6], "## Sibling")
end

-- ============================================================================
-- create_node Tests
-- ============================================================================

T["create_node - creates valid heading node"] = function()
	local node = document.create_node({
		level = 2,
		text = "New Task",
		state = "TODO",
	})
	MiniTest.expect.equality(node.type, "heading")
	MiniTest.expect.equality(node.level, 2)
	MiniTest.expect.equality(node.parsed.state, "TODO")
	MiniTest.expect.equality(node.parsed.text, "New Task")
	MiniTest.expect.equality(node.dirty, true)
end

T["create_node - creates node with priority and tags"] = function()
	local node = document.create_node({
		level = 1,
		text = "Important",
		state = "TODO",
		priority = "A",
		tags = { "work", "urgent" },
	})
	MiniTest.expect.equality(node.parsed.priority, "A")
	MiniTest.expect.equality(#node.parsed.tags, 2)
	MiniTest.expect.equality(node.parsed.tags[1], "work")
end

T["create_node - creates node with content lines"] = function()
	local node = document.create_node({
		level = 2,
		text = "Task",
		content_lines = { "Some content", "More content" },
	})
	MiniTest.expect.equality(#node.content_lines, 2)
	MiniTest.expect.equality(node.content_lines[1], "Some content")
end

T["create_node - serializes correctly"] = function()
	local node = document.create_node({
		level = 2,
		text = "Task",
		state = "TODO",
		priority = "A",
	})

	-- Create a root and add the node
	local root = document.parse({})
	document.insert_child(root, node)

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## TODO [#A] Task")
end

-- ============================================================================
-- insert_child Tests
-- ============================================================================

T["insert_child - appends child to parent"] = function()
	local lines = { "## Parent" }
	local root = document.parse(lines)
	local parent = root.children[1]

	local child = document.create_node({
		level = 3,
		text = "Child",
	})

	document.insert_child(parent, child)

	MiniTest.expect.equality(#parent.children, 1)
	MiniTest.expect.equality(parent.children[1].parsed.text, "Child")
end

T["insert_child - inserts at position"] = function()
	local lines = {
		"## Parent",
		"### First",
		"### Third",
	}
	local root = document.parse(lines)
	local parent = root.children[1]

	local second = document.create_node({
		level = 3,
		text = "Second",
	})

	document.insert_child(parent, second, 2)

	MiniTest.expect.equality(#parent.children, 3)
	MiniTest.expect.equality(parent.children[1].parsed.text, "First")
	MiniTest.expect.equality(parent.children[2].parsed.text, "Second")
	MiniTest.expect.equality(parent.children[3].parsed.text, "Third")
end

T["insert_child - marks parent as dirty"] = function()
	local root = document.parse({})
	local child = document.create_node({ level = 1, text = "Child" })

	document.insert_child(root, child)

	MiniTest.expect.equality(root.dirty, true)
end

T["insert_child - serializes in correct order"] = function()
	local root = document.parse({})

	local first = document.create_node({ level = 1, text = "First" })
	local second = document.create_node({ level = 1, text = "Second" })

	document.insert_child(root, first)
	document.insert_child(root, second)

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "# First")
	MiniTest.expect.equality(output[2], "# Second")
end

-- ============================================================================
-- find_heading_by_text Tests
-- ============================================================================

T["find_heading_by_text - finds top-level heading"] = function()
	local lines = {
		"## First",
		"## Second",
		"## Third",
	}
	local root = document.parse(lines)

	local found = document.find_heading_by_text(root, "Second")

	MiniTest.expect.no_equality(found, nil)
	MiniTest.expect.equality(found.parsed.text, "Second")
end

T["find_heading_by_text - finds nested heading"] = function()
	local lines = {
		"## Parent",
		"### Child",
		"#### Grandchild",
	}
	local root = document.parse(lines)

	local found = document.find_heading_by_text(root, "Grandchild")

	MiniTest.expect.no_equality(found, nil)
	MiniTest.expect.equality(found.level, 4)
end

T["find_heading_by_text - returns nil when not found"] = function()
	local lines = { "## Heading" }
	local root = document.parse(lines)

	local found = document.find_heading_by_text(root, "Missing")

	MiniTest.expect.equality(found, nil)
end

T["find_heading_by_text - finds heading with state"] = function()
	local lines = { "## TODO Important Task" }
	local root = document.parse(lines)

	local found = document.find_heading_by_text(root, "Important Task")

	MiniTest.expect.no_equality(found, nil)
	MiniTest.expect.equality(found.parsed.state, "TODO")
end

-- ============================================================================
-- adjust_node_levels Tests
-- ============================================================================

T["adjust_node_levels - adjusts single node level"] = function()
	local node = document.create_node({ level = 1, text = "Task" })

	document.adjust_node_levels(node, 2)

	MiniTest.expect.equality(node.level, 3)
	MiniTest.expect.equality(node.dirty, true)
end

T["adjust_node_levels - adjusts levels recursively"] = function()
	local lines = {
		"## TODO Task",
		"### Subtask",
	}
	local root = document.parse(lines)
	local parent = root.children[1]

	document.adjust_node_levels(parent, 1)

	MiniTest.expect.equality(parent.level, 3)
	MiniTest.expect.equality(parent.children[1].level, 4)
end

T["adjust_node_levels - serializes with adjusted levels"] = function()
	local lines = {
		"# Task",
		"## Subtask",
	}
	local root = document.parse(lines)

	document.adjust_node_levels(root.children[1], 1)

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "## Task")
	MiniTest.expect.equality(output[2], "### Subtask")
end

-- ============================================================================
-- File I/O Tests
-- ============================================================================

T["read_from_file and write_to_file - round trip"] = function()
	local test_file = "/tmp/org-markdown-test-doc.md"
	local original_lines = {
		"## TODO Task",
		"Content here",
	}

	-- Write original using utils
	local utils = require("org_markdown.utils.utils")
	utils.write_lines(test_file, original_lines)

	-- Read with document model
	local root = document.read_from_file(test_file)
	MiniTest.expect.equality(#root.children, 1)
	MiniTest.expect.equality(root.children[1].parsed.state, "TODO")

	-- Modify
	root.children[1]:set_state("DONE")

	-- Write back
	document.write_to_file(test_file, root)

	-- Read again and verify
	local final = document.read_from_file(test_file)
	MiniTest.expect.equality(final.children[1].parsed.state, "DONE")

	-- Cleanup
	vim.fn.delete(test_file)
end

T["read_from_file - handles non-existent file"] = function()
	local root = document.read_from_file("/tmp/does-not-exist-12345.md")
	MiniTest.expect.equality(root.type, "document")
	MiniTest.expect.equality(#root.children, 0)
end

-- ============================================================================
-- Integration: Insert Under Heading Pattern
-- ============================================================================

T["integration - insert content under existing heading"] = function()
	local lines = {
		"# Inbox",
		"",
		"# Archive",
	}
	local root = document.parse(lines)

	-- Find the Inbox heading
	local inbox = document.find_heading_by_text(root, "Inbox")
	MiniTest.expect.no_equality(inbox, nil)

	-- Create a new task and insert it
	local task = document.create_node({
		level = 2,
		text = "New capture",
		state = "TODO",
	})

	document.insert_child(inbox, task)

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "# Inbox")
	MiniTest.expect.equality(output[2], "")
	MiniTest.expect.equality(output[3], "## TODO New capture")
	MiniTest.expect.equality(output[4], "# Archive")
end

T["integration - insert content when heading doesn't exist"] = function()
	local lines = { "Some document content" }
	local root = document.parse(lines)

	-- Try to find heading that doesn't exist
	local target = document.find_heading_by_text(root, "Inbox")
	MiniTest.expect.equality(target, nil)

	-- Create the heading
	target = document.create_node({
		level = 1,
		text = "Inbox",
	})
	document.insert_child(root, target)

	-- Add a task under it
	local task = document.create_node({
		level = 2,
		text = "New task",
		state = "TODO",
	})
	document.insert_child(target, task)

	local output = document.serialize(root)
	MiniTest.expect.equality(output[1], "Some document content")
	MiniTest.expect.equality(output[2], "# Inbox")
	MiniTest.expect.equality(output[3], "## TODO New task")
end

return T
