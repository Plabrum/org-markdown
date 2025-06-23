local agenda = require("org_markdown.agenda")
local capture = require("org_markdown.capture")
local refile = require("org_markdown.refile")
local config = require("org_markdown.config")
local find = require("org_markdown.find")

local M = {}

function M.register()
	vim.api.nvim_create_user_command("MarkdownCapture", function(opts)
		capture.capture_template(opts.args ~= "" and opts.args or nil)
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(require("org_markdown.config").capture_templates)
		end,
	})

	vim.api.nvim_create_user_command("MarkdownRefileFile", refile.to_file, {
		desc = "OrgMarkdown: Refile to File",
	})

	-- vim.api.nvim_create_user_command("MarkdownRefileHeading", refile.to_heading, {
	-- 	desc = "OrgMarkdown: Refile to Heading",
	-- })

	vim.api.nvim_create_user_command("MarkdownAgendaCalendar", agenda.show_calendar, {
		desc = "OrgMarkdown: Agenda Calendar View",
	})

	vim.api.nvim_create_user_command("MarkdownAgendaTasks", agenda.show_tasks, {
		desc = "OrgMarkdown: Agenda Task View",
	})

	vim.api.nvim_create_user_command("MarkdownAgenda", agenda.show_combined, {
		desc = "OrgMarkdown: Agenda Combined View",
	})

	vim.api.nvim_create_user_command("MarkdownFindFile", find.open_file_picker, {
		desc = "OrgMarkdown: Open Markdown File",
	})

	-- vim.api.nvim_create_user_command("MarkdownFindHeading", find.open_heading_picker, {
	-- 	desc = "OrgMarkdown: Open Heading in File",
	-- })

	-- Add configurable keymaps
	local keymaps = config.keymaps or {}
	vim.keymap.set("n", keymaps.capture, "<cmd>MarkdownCapture<CR>", {
		desc = "OrgMarkdown: Capture",
		silent = true,
	})

	vim.keymap.set("n", keymaps.agenda, "<cmd>MarkdownAgenda<CR>", {
		desc = "OrgMarkdown: Agenda View",
		silent = true,
	})

	vim.keymap.set("n", keymaps.find_file, "<cmd>MarkdownFindFile<CR>", {
		desc = "OrgMarkdown: Find Markdown File",
		silent = true,
	})

	-- vim.keymap.set("n", keymaps.find_heading, "<cmd>MarkdownFindHeading<CR>", {
	-- 	desc = "OrgMarkdown: Find Heading in File",
	-- 	silent = true,
	-- })

	vim.keymap.set("n", keymaps.refile_to_file, "<cmd>MarkdownRefileFile<CR>", {
		desc = "OrgMarkdown: Refile to file",
		silent = true,
	})

	-- vim.keymap.set("n", keymaps.refile_to_heading, "<cmd>MarkdownRefileHeading<CR>", {
	-- 	desc = "OrgMarkdown: Refile to heading",
	-- 	silent = true,
	-- })
end
return M
