local M = {
	agenda_files = { "~/notes", "~/projects" },
	default_tags = { "todo", "inbox" },
	capture_templates = {},
	default_capture = "inbox",
	window_method = "float",
	picker = "telescope", -- or "snacks"
	refile_paths = { "~/notes", "~/projects" },
	keymaps = {
		capture = "<leader>on",
		agenda = "<leader>ov",
	},
}

function M.setup(user_config)
	for k, v in pairs(user_config or {}) do
		M[k] = v
	end
end

return M
