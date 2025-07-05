# Org_markdown

Org markdown gives org mode features to markdown files in Neovim.

### Features
  * Agenda view for scheduled tasks using <YYYY-MM-DD>
  * Task management for TODO and IN_PROGRESS headings
  *  Priority-aware task sorting ([#A], [#B], etc.)
  *  Refile entries to other headings or files
  *  Flexible capture templates with floating editor support
  *  Picker support via telescope.nvim or snacks.nvim
  *  Fully configurable with lazy-loading and custom keymaps


### Getting Started

Installation (with Lazy.nvim)

```lua
return {
  "Plabrum/org-markdown",
  opts = {
 }
```


### Commands

Command	Description
:MarkdownCapture	Create a new capture
:MarkdownAgenda	Combined agenda view
:MarkdownAgendaTasks	Task view sorted by priority
:MarkdownAgendaCalendar	Calendar view (7-day range)
:MarkdownRefileFile	Refile content to a file
:MarkdownRefileHeading	Refile content under a heading



### Refiling
  - Call :MarkdownRefileFile or :MarkdownRefileHeading
  - Picker shows Markdown files or headings
  - Refile automatically cuts the content and pastes it to the destination
  - Operates on bullet lines or heading blocks based on cursor position


### Agenda Rules

Tasks Tracked
  - Lines with `TODO` or `IN_PROGRESS`
  - Example: `## TODO Implement capture buffer`

Scheduled Dates
  - Use `<2025-06-21>` for tracked items
  - Use `[2025-06-21]` for non-agenda timestamps

Priorities
  - Supported: [#A], [#B], [#C]
  - Tasks are ranked in AgendaTasks


### Configuration Options

```lua
opts = {
  keymaps = {
    capture = "<leader>on",
    agenda = "<leader>ov",
  },
  picker = "telescope", -- or "snacks"
  window_method = "float", -- or "horizontal"
  captures = {
    default_template = "inbox",
    templates = {
      inbox = {
        file = "~/notes/inbox.md",
        heading = "Inbox",
        template = "- [ ] %t %?",
      },
    },
  }
}
```


### TODO
  - Tag filtering in agenda views
  - Jump to line from agenda view
  - Multiple refiles at once
  - Archive support


