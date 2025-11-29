local M = {
	captures = {
		window_method = "horizontal",
		default_template = "todo",
		templates = {
			["todo"] = {
				template = "# TODO %? \n %u",
				filename = "~/notes/todo.md",
				heading = "TODO's",
			},
			["notes"] = {
				template = "#  %?",
				filename = "~/notes/notes.md",
				heading = "Notes",
			},
		},
	},
	agendas = {
		window_method = "float",
	},
	window_method = "vertical",
	picker = "snacks", -- or "telescope"
	-- picker = "telescope",
	refile_paths = { "~/notes" },
	quick_note_file = "~/notes/quick_notes/",
	sync = {
		enabled = true,
		plugins = {
			-- Plugins will register their default config here
		},
		sync_all_command = "MarkdownSyncAll",
	},
	keymaps = {
		capture = "<leader>oc",
		agenda = "<leader>oa",
		find_file = "<leader>of",
		find_heading = "<leader>oh",
		refile_to_file = "<leader>orf",
		refile_to_heading = "<leader>orh",
		open_quick_note = "<leader>z",
		sync_all = "<leader>oS",
	},
	checkbox_states = {
		" ",
		"-",
		"X",
	},
	status_states = {
		"TODO",
		"IN_PROGRESS",
		"DONE",
	},

	-- TODO PAL: Implement front matter automations
	-- automation = {
	-- 	tags = {
	-- 		moab = {
	-- 			on_enter = function(filename)
	-- 				return vim.fn.input("Tag: ")
	-- 			end,
	-- 			on_exit = function(filename) end,
	-- 		},
	-- 	},
	-- },
}

local function merge_tables(default, user)
	for k, v in pairs(user) do
		if type(v) == "table" and type(default[k]) == "table" then
			merge_tables(default[k], v)
		else
			default[k] = v
		end
	end
end

function M.setup(user_config)
	merge_tables(M, user_config or {})
end

return M
