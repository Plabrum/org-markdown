local M = {}
local datetime = require("org_markdown.utils.datetime")

function M.format_date(date_str)
	-- Delegate to datetime module
	return datetime.format_display(date_str)
end

return M
