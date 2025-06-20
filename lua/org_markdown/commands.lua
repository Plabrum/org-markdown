local agenda = require("org_markdown.agenda")
local capture = require("org_markdown.capture")
local refile = require("org_markdown.refile")
local config = require("org_markdown.config")

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

	vim.api.nvim_create_user_command("MarkdownRefileFile", refile.to_file, {})
	vim.api.nvim_create_user_command("MarkdownRefileHeading", refile.to_heading, {})

	vim.api.nvim_create_user_command("MarkdownAgendaCalendar", function()
		agenda.show_calendar()
	end, {})

	vim.api.nvim_create_user_command("MarkdownAgendaTasks", function()
		agenda.show_tasks()
	end, {})

	vim.api.nvim_create_user_command("MarkdownAgenda", function()
		agenda.show_combined()
	end, {})

	-- Add configurable keymaps
	local keymaps = config.keymaps or {}
	vim.keymap.set("n", keymaps.capture or "<leader>on", "<cmd>MarkdownCapture<CR>", {
		desc = "OrgMarkdown: Capture",
		silent = true,
	})

	vim.keymap.set("n", keymaps.agenda or "<leader>ov", "<cmd>MarkdownAgenda<CR>", {
		desc = "OrgMarkdown: Agenda View",
		silent = true,
	})
end
return M
