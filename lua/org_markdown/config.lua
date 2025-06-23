local M = {
	default_tags = { "todo", "inbox" },
	capture_templates = {},
	default_capture = "inbox",
	window_method = "float",
	picker = "telescope", -- or "snacks"
	refile_paths = { "~/notes", "~/projects" },
	keymaps = {
		capture = "<leader>onn",
		agenda = "<leader>onv",
		find_file = "<leader>onf",
		find_heading = "<leader>onh",
		refile_to_file = "<leader>onrf",
		refile_to_heading = "<leader>onrh",
	},
}

function M.setup(user_config)
	for k, v in pairs(user_config or {}) do
		M[k] = v
	end
end

return M
