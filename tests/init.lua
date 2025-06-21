-- Ensure predictable working directory
local cwd = vim.fn.getcwd()

-- Ensure your plugin and lazy.nvim are in the runtime path
vim.opt.rtp:prepend(cwd)
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

-- Bootstrap Lazy.nvim with your plugin and mini.test
require("lazy").setup({
	{
		dir = cwd,
		name = "org_markdown",
		dependencies = {
			{ "echasnovski/mini.test", version = false },
		},
	},
}, {
	root = cwd .. "/.lazy",
	defaults = { lazy = false },
})

-- Run mini.test after plugins are fully loaded
vim.schedule(function()
	require("mini.test").setup()
	require("mini.test").run()
end)
