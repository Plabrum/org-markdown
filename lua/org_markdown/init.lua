local M = {}

function M.setup(opts)
	require("org_markdown.config").setup(opts or {})
	require("org_markdown.commands").register()
end

return M
