local M = {}

function M.format_date(date_str)
	local y, m, d = date_str:match("(%d+)%-(%d+)%-(%d+)")
	local time = os.time({ year = y, month = m, day = d })
	return os.date("%A %d %b", time)
end

return M
