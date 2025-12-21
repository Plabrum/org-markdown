local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local tree = require("org_markdown.utils.tree")

-- ============================================================================
-- Primitives Tests
-- ============================================================================

T["get_level - returns level for h1"] = function()
  MiniTest.expect.equality(tree.get_level("# Heading"), 1)
end

T["get_level - returns level for h2"] = function()
  MiniTest.expect.equality(tree.get_level("## Heading"), 2)
end

T["get_level - returns level for h3"] = function()
  MiniTest.expect.equality(tree.get_level("### Heading"), 3)
end

T["get_level - returns nil for non-heading"] = function()
  MiniTest.expect.equality(tree.get_level("Not a heading"), nil)
end

T["get_level - returns nil for hashes without space"] = function()
  MiniTest.expect.equality(tree.get_level("##NoSpace"), nil)
end

T["get_level - returns nil for empty line"] = function()
  MiniTest.expect.equality(tree.get_level(""), nil)
end

T["get_level - handles heading with content"] = function()
  MiniTest.expect.equality(tree.get_level("## TODO [#A] Task :tag:"), 2)
end

T["is_heading - returns true for heading"] = function()
  MiniTest.expect.equality(tree.is_heading("## Heading"), true)
end

T["is_heading - returns false for non-heading"] = function()
  MiniTest.expect.equality(tree.is_heading("Not a heading"), false)
end

T["is_heading - returns false for empty line"] = function()
  MiniTest.expect.equality(tree.is_heading(""), false)
end

-- ============================================================================
-- find_end Tests
-- ============================================================================

T["find_end - finds end at same level heading"] = function()
  local lines = {
    "## Heading 1",
    "Content line",
    "## Heading 2",
    "More content",
  }
  MiniTest.expect.equality(tree.find_end(lines, 1, 2), 2)
end

T["find_end - finds end at higher level heading"] = function()
  local lines = {
    "## Heading 1",
    "Content line",
    "# Higher level",
  }
  MiniTest.expect.equality(tree.find_end(lines, 1, 2), 2)
end

T["find_end - includes nested headings"] = function()
  local lines = {
    "## Parent",
    "### Child",
    "Content",
    "## Next sibling",
  }
  MiniTest.expect.equality(tree.find_end(lines, 1, 2), 3)
end

T["find_end - returns last line if no ending heading"] = function()
  local lines = {
    "## Heading",
    "Content 1",
    "Content 2",
  }
  MiniTest.expect.equality(tree.find_end(lines, 1, 2), 3)
end

T["find_end - handles deeply nested structure"] = function()
  local lines = {
    "# Level 1",
    "## Level 2",
    "### Level 3",
    "#### Level 4",
    "Content",
    "## Another Level 2",
  }
  MiniTest.expect.equality(tree.find_end(lines, 2, 2), 5)
end

-- ============================================================================
-- find_children Tests
-- ============================================================================

T["find_children - finds direct children only"] = function()
  local lines = {
    "## Parent",
    "### Child 1",
    "#### Grandchild",
    "### Child 2",
    "## Sibling",
  }
  local children = tree.find_children(lines, 1, 2)
  MiniTest.expect.equality(#children, 2)
  MiniTest.expect.equality(children[1].line, 2)
  MiniTest.expect.equality(children[1].level, 3)
  MiniTest.expect.equality(children[2].line, 4)
  MiniTest.expect.equality(children[2].level, 3)
end

T["find_children - returns empty for heading with no children"] = function()
  local lines = {
    "## Heading",
    "Content only",
    "## Next heading",
  }
  local children = tree.find_children(lines, 1, 2)
  MiniTest.expect.equality(#children, 0)
end

T["find_children - stops at sibling boundary"] = function()
  local lines = {
    "## Parent",
    "### Child",
    "## Sibling",
    "### Not a child",
  }
  local children = tree.find_children(lines, 1, 2)
  MiniTest.expect.equality(#children, 1)
  MiniTest.expect.equality(children[1].line, 2)
end

-- ============================================================================
-- get_block Tests
-- ============================================================================

T["get_block - returns range for heading with content"] = function()
  local lines = {
    "## Heading",
    "Content 1",
    "Content 2",
    "## Next",
  }
  local start_line, end_line = tree.get_block(lines, 1, 2)
  MiniTest.expect.equality(start_line, 1)
  MiniTest.expect.equality(end_line, 3)
end

T["get_block - includes nested headings"] = function()
  local lines = {
    "## Parent",
    "### Child",
    "Content",
    "## Sibling",
  }
  local start_line, end_line = tree.get_block(lines, 1, 2)
  MiniTest.expect.equality(start_line, 1)
  MiniTest.expect.equality(end_line, 3)
end

T["get_block - auto-detects level"] = function()
  local lines = {
    "### Heading",
    "Content",
    "### Next",
  }
  local start_line, end_line = tree.get_block(lines, 1)
  MiniTest.expect.equality(start_line, 1)
  MiniTest.expect.equality(end_line, 2)
end

T["get_block - returns same line for non-heading"] = function()
  local lines = {
    "Not a heading",
    "Content",
  }
  local start_line, end_line = tree.get_block(lines, 1)
  MiniTest.expect.equality(start_line, 1)
  MiniTest.expect.equality(end_line, 1)
end

-- ============================================================================
-- extract_block Tests
-- ============================================================================

T["extract_block - extracts all lines in block"] = function()
  local lines = {
    "## Heading",
    "Content 1",
    "Content 2",
    "## Next",
  }
  local block = tree.extract_block(lines, 1, 2)
  MiniTest.expect.equality(#block, 3)
  MiniTest.expect.equality(block[1], "## Heading")
  MiniTest.expect.equality(block[2], "Content 1")
  MiniTest.expect.equality(block[3], "Content 2")
end

T["extract_block - includes nested headings"] = function()
  local lines = {
    "## Parent",
    "### Child",
    "#### Grandchild",
    "Content",
    "## Sibling",
  }
  local block = tree.extract_block(lines, 1, 2)
  MiniTest.expect.equality(#block, 4)
  MiniTest.expect.equality(block[2], "### Child")
  MiniTest.expect.equality(block[3], "#### Grandchild")
end

-- ============================================================================
-- find_heading Tests
-- ============================================================================

T["find_heading - finds heading by exact text"] = function()
  local lines = {
    "## First",
    "Content",
    "## Target",
    "More content",
    "## Third",
  }
  local line, level, end_line = tree.find_heading(lines, "Target")
  MiniTest.expect.equality(line, 3)
  MiniTest.expect.equality(level, 2)
  MiniTest.expect.equality(end_line, 4)
end

T["find_heading - returns nil for not found"] = function()
  local lines = {
    "## First",
    "## Second",
  }
  local line, level, end_line = tree.find_heading(lines, "NotFound")
  MiniTest.expect.equality(line, nil)
  MiniTest.expect.equality(level, nil)
  MiniTest.expect.equality(end_line, nil)
end

T["find_heading - handles special regex characters in text"] = function()
  local lines = {
    "## Test (with parens)",
    "Content",
  }
  local line, level, end_line = tree.find_heading(lines, "Test (with parens)")
  MiniTest.expect.equality(line, 1)
  MiniTest.expect.equality(level, 2)
end

T["find_heading - matches different heading levels"] = function()
  local lines = {
    "# H1",
    "### H3",
    "## H2",
  }
  local line, level, _ = tree.find_heading(lines, "H3")
  MiniTest.expect.equality(line, 2)
  MiniTest.expect.equality(level, 3)
end

-- ============================================================================
-- Edge Cases
-- ============================================================================

T["handles empty file"] = function()
  local lines = {}
  MiniTest.expect.equality(tree.find_end(lines, 1, 1), 0)
  MiniTest.expect.equality(#tree.find_children(lines, 1, 1), 0)
end

T["handles single heading file"] = function()
  local lines = { "## Only heading" }
  MiniTest.expect.equality(tree.find_end(lines, 1, 2), 1)
  local block = tree.extract_block(lines, 1, 2)
  MiniTest.expect.equality(#block, 1)
end

T["handles heading at end of file"] = function()
  local lines = {
    "## First",
    "Content",
    "## Last",
  }
  local _, end_line = tree.get_block(lines, 3, 2)
  MiniTest.expect.equality(end_line, 3)
end

return T
