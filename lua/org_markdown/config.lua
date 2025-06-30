local M = {
	capture_templates = {
		["todo"] = {
			template = "# TODO %? \n %u",
			name = "Todo",
			header = "TODO's",
		},
		["notes"] = {
			template = "#  %?",
			name = "Notes",
			header = "Notes",
		},
	},
	default_capture = "todo",
	window_method = "float",
	picker = "snacks", -- or "telescope"
	refile_paths = { "~/notes" },
	quick_note_file = "~/notes/quick_notes/",
	keymaps = {
		capture = "<leader>onn",
		agenda = "<leader>onv",
		find_file = "<leader>onf",
		find_heading = "<leader>onh",
		refile_to_file = "<leader>onrf",
		refile_to_heading = "<leader>onrh",
		open_quick_note = "<leader>z",
	},
}

function M.setup(user_config)
	for k, v in pairs(user_config or {}) do
		M[k] = v
	end
end

return M
