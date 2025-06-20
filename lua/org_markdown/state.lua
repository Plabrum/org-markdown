local M = {
	tasks = {},
	headings = {},
	metadata = {},
}

function M.set_data(data)
	M.tasks = data.tasks or {}
	M.headings = data.headings or {}
	M.metadata = data.metadata or {}
end

function M.get_tasks()
	return M.tasks
end

return M
