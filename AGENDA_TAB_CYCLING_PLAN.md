# Agenda Tab Cycling Implementation Plan

## Current State Analysis

### Agenda Views Overview

The agenda system has **three distinct views**, each accessible via separate Vim commands:

#### 1. **Show Calendar View** (`M.show_calendar()`)
- **Command:** `:MarkdownAgendaCalendar`
- **Purpose:** Display a 7-day calendar with scheduled items
- **Structure:**
  - Groups tasks by date (next 7 days)
  - Shows each date with `formatter.format_date(date)`
  - Lists items under each day with prefix `    •` (indented 4 spaces)
  - Items show: state, priority `[#A/B/C]`, and title
- **Keybindings:** 
  - `<CR>` - Jump to file and line where task is defined
  - `q` / `<Esc>` - Close window (set via `utils.open_window()`)

#### 2. **Show Tasks View** (`M.show_tasks()`)
- **Command:** `:MarkdownAgendaTasks`
- **Purpose:** Display all tasks sorted by priority
- **Structure:**
  - Title: "AgendaTask (by priority)"
  - Sorted by priority: A > B > C > Z (default)
  - Format: `  [#A] TODO        task_title (filename.md)`
- **Keybindings:**
  - `<CR>` - Jump to file and line
  - `q` / `<Esc>` - Close window

#### 3. **Show Combined View** (`M.show_combined()`)
- **Command:** `:MarkdownAgenda` (registered as main agenda command)
- **Purpose:** Display both task and calendar views in one window
- **Structure:**
  - Tasks section (by priority) at top
  - Separator line (dashes spanning window width)
  - Calendar section below (7-day view)
  - All items are navigable via `<CR>`
- **Keybindings:**
  - `<CR>` - Jump to file/line based on clicked item
  - `q` / `<Esc>` - Close window
- **Window Method:** Uses `config.agendas.window_method` (currently "float")

### Key Architecture Points

#### Data Structure: line_to_item Mapping
Each view builds a `line_to_item` table that maps display line numbers to agenda items:
```lua
line_to_item[#lines] = {
  title = heading.text,
  state = heading.state,       -- TODO, IN_PROGRESS, DONE, etc.
  priority = heading.priority, -- A, B, C
  date = heading.tracked,      -- YYYY-MM-DD (or nil)
  line = i,                    -- Line number in source file
  file = file,                 -- Full path to markdown file
  tags = heading.tags,         -- Table of tags
  source = filename,           -- Just the filename
}
```

#### Window Management via `utils.open_window()`
All agenda views use `utils.open_window(opts)` which:
- Creates a buffer with `create_buffer(opts)`
- Opens window using method: `config.agendas.window_method` (or specified method)
- Returns: `buf, win` (buffer ID and window ID)
- Sets keybindings for `q`, `<Esc>` to close
- Supports window methods: "float", "horizontal", "vertical", "vsplit", "inline_prompt"

#### Keymap Setup
Currently, keymaps are set **locally to each buffer** using:
```lua
vim.keymap.set("n", "<CR>", function() ... end, { buffer = buf, silent = true })
```

This is done inside each view function (`show_calendar()`, `show_tasks()`, `show_combined()`).

#### Highlight System
Custom highlights are applied for task states:
- `OrgTodo` - Red (#ff5f5f)
- `OrgInProgress` - Yellow (#f0c000)
- `OrgDone` - Green (#5fd75f)
- `OrgTitle` - Blue (#87afff)

### Current Changes (Not Yet Committed)

The repository currently has uncommitted changes that add:

1. **line_to_item mapping to all views** - Each view now returns both lines and a mapping table
2. **<CR> keybinding for all views** - Allows jumping to the source file/line of any task
3. **Autocmd for editing keybinds** - Sets up task cycling keybinds on markdown files (in `commands.lua`)
4. **Enhanced footer text** - Shows "Press <CR> to jump to file, q to close"

## Tab Cycling Implementation Strategy

### Design Approach

To add `[` and `]` keybindings for cycling between the three views:

1. **Store View State:** Keep track of which view is currently displayed
2. **Maintain Window/Buffer:** Persist the window/buffer and swap content instead of closing/reopening
3. **Add Navigation Keybindings:** Set `[` to go to previous view, `]` to go to next view
4. **Update Content:** Re-render the displayed content while keeping the same buffer/window
5. **Preserve Cursor Position:** Try to keep cursor on similar items when switching views

### Implementation Plan

#### Option A: Reuse Window with Content Swapping (Recommended)

**Advantages:**
- Single window persists across all views
- Fast switching without flicker
- Can preserve approximate cursor position
- Minimal disruption to existing code

**Changes needed:**
1. Create wrapper function `M.show_agenda_tabbed()` that:
   - Stores current view state in buffer variable: `vim.b[buf].agenda_view`
   - Opens window once
   - Sets up cycling keybindings for `[` and `]`
   
2. Add helper function to swap view content:
   - Gets current view from buffer variable
   - Renders new view content
   - Swaps lines via `vim.api.nvim_buf_set_lines()`
   - Updates `line_to_item` mapping in buffer variable
   - Updates highlights

3. Cycling logic:
   - Views order: "combined" → "tasks" → "calendar" → "combined"
   - On `]`: next view
   - On `[`: previous view

#### Option B: Store State and Update Existing Functions

Less intrusive but requires modifying each `show_*` function to accept optional `persist` parameter.

### Proposed Buffer Variables

Store state in buffer variable namespace:
- `vim.b[buf].agenda_view` - Current view: "combined", "tasks", or "calendar"
- `vim.b[buf].agenda_lines` - Current display lines
- `vim.b[buf].agenda_line_to_item` - Current line-to-item mapping
- `vim.b[buf].agenda_buf` - Buffer ID (for cleanup)
- `vim.b[buf].agenda_win` - Window ID (for cleanup)

### Keybinding Integration Points

The `[` and `]` keybindings would be set in the cycling wrapper function:
```lua
vim.keymap.set("n", "]", function()
  -- Get current view, cycle to next, update buffer
end, { buffer = buf, silent = true })

vim.keymap.set("n", "[", function()
  -- Get current view, cycle to previous, update buffer
end, { buffer = buf, silent = true })
```

### File Modifications Required

1. **`agenda.lua`:**
   - Add `M.show_agenda_tabbed()` - main entry point for tabbed cycling
   - Add internal helper `update_view_content(buf, view_type)` - reusable view renderer
   - Refactor existing `get_*_lines()` to be used by both old and new code paths

2. **`commands.lua`:**
   - Update `:MarkdownAgenda` command to call `show_agenda_tabbed()` instead of `show_combined()`
   - Consider keeping `:MarkdownAgendaCalendar` and `:MarkdownAgendaTasks` as direct access points

3. **Configuration (Optional):**
   - Add keybindings to config for `[` and `]` cycling (or use defaults)

### Testing Considerations

1. Verify window reuse works across all three views
2. Check that `<CR>` jump functionality works from all views
3. Confirm highlights re-apply correctly when switching views
4. Test that closing with `q` properly cleans up
5. Verify cursor position handling (or acceptance that it resets)

## Implementation Notes

### Why This Approach?

1. **Minimal refactoring:** Existing view functions can remain mostly unchanged
2. **Persistent UI:** Single window feels more cohesive
3. **Fast switching:** No flicker from closing/reopening windows
4. **Extension-friendly:** Easy to add more views later

### Current Keybinding System

- Global keybindings set in `commands.lua`
- Buffer-local keybindings set within each view function
- Editing keybindings set via `editing.setup_editing_keybinds()` (with guard to prevent re-setting)

The tabbed cycling keybindings should be buffer-local like the `<CR>` jump binding.

### Footer Update

The footer should probably be updated to show cycling info:
```
"Press [ / ] to cycle views, <CR> to jump, q to close"
```

## Summary

**Three views exist:**
- **Combined:** Tasks + Calendar (default, most useful)
- **Tasks:** Priority-sorted task list
- **Calendar:** 7-day date-based view

**Current architecture:**
- Each view creates its own window via `utils.open_window()`
- Returns `buf, win` IDs
- Sets local keybindings (mostly `<CR>` for jumping)
- Closes on `q` / `<Esc>`

**For tab cycling:**
- Create wrapper function to manage view state
- Persist window/buffer across view switches
- Use `[` and `]` keybindings to cycle
- Update display content without closing window
- Minimal changes to existing code
