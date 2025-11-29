local agenda = require("org_markdown.agenda")
local capture = require("org_markdown.capture")
local refile = require("org_markdown.refile")
local config = require("org_markdown.config")
local find = require("org_markdown.find")
local editing = require("org_markdown.utils.editing")
local quick_note = require("org_markdown.quick_note")

local M = {}

-- Helper function to convert names to PascalCase
local function name_to_pascal(name)
	-- Convert names like "urgent_work" or "urgent-work" to "UrgentWork"
	return name:gsub("[%s_%-]+(%w)", function(c)
		return c:upper()
	end):gsub("^(%l)", string.upper)
end

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

	vim.api.nvim_create_user_command("MarkdownAgenda", agenda.show_tabbed_agenda, {
		desc = "OrgMarkdown: Agenda Tabbed View",
	})

	-- Auto-register view commands
	if config.agendas.register_view_commands ~= false then
		for view_id, view_def in pairs(config.agendas.views or {}) do
			local cmd_name = "MarkdownAgenda" .. name_to_pascal(view_id)

			vim.api.nvim_create_user_command(cmd_name, function()
				agenda.show_view(view_id)
			end, {
				desc = "OrgMarkdown: " .. (view_def.title or view_id),
			})
		end
	end

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

	vim.api.nvim_create_augroup("OrgMarkdownEditing", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = "OrgMarkdownEditing",
		pattern = { "markdown", "markdown.mdx", "quarto" }, -- add/trim as you like
		callback = function(args)
			-- Only activate when you want (e.g., not in help buffers, etc.)
			-- if vim.bo[args.buf].buftype ~= "" then return end
			editing.setup_editing_keybinds(args.buf)
		end,
	})
	-- vim.keymap.set("n", keymaps.refile_to_heading, "<cmd>MarkdownRefileHeading<CR>", {
	-- 	desc = "OrgMarkdown: Refile to heading",
	-- 	silent = true,
	-- })

	for name, recipe in pairs(quick_note.recipes) do
		-- 1. Create the user command
		if name and recipe then
			local command_name = "OrgMarkdown" .. name_to_pascal(recipe.title)
			vim.api.nvim_create_user_command(command_name, function()
				quick_note.open_quick_note(name)
			end, {
				desc = "OrgMarkdown: " .. recipe.title,
			})

			-- 2. Bind the key if recipe.key is not empty
			if recipe.key and recipe.key ~= "" then
				local key = keymaps.open_quick_note .. recipe.key
				vim.keymap.set("n", key, "<cmd>" .. command_name .. "<CR>", {
					desc = "OrgMarkdown: " .. recipe.title,
					silent = true,
				})
			end
		end
	end

	-- Register sync commands dynamically
	local sync_manager = require("org_markdown.sync.manager")

	-- Register sync all command
	vim.api.nvim_create_user_command(config.sync.sync_all_command or "MarkdownSyncAll", function()
		sync_manager.sync_all()
	end, { desc = "OrgMarkdown: Sync all enabled plugins" })

	-- Register per-plugin commands
	for plugin_name, plugin in pairs(sync_manager.plugins) do
		local cmd_name = plugin.command_name or ("MarkdownSync" .. name_to_pascal(plugin_name))

		vim.api.nvim_create_user_command(cmd_name, function()
			sync_manager.sync_plugin(plugin_name)
		end, {
			desc = "OrgMarkdown: " .. (plugin.description or ("Sync " .. plugin_name)),
		})

		-- Register keymap if specified
		if plugin.keymap then
			vim.keymap.set("n", plugin.keymap, function()
				sync_manager.sync_plugin(plugin_name)
			end, { desc = "OrgMarkdown: Sync " .. plugin_name, silent = true })
		end
	end

	-- Register sync all keymap
	if keymaps.sync_all then
		vim.keymap.set("n", keymaps.sync_all, "<cmd>" .. (config.sync.sync_all_command or "MarkdownSyncAll") .. "<CR>", {
			desc = "OrgMarkdown: Sync All",
			silent = true,
		})
	end
end
return M
