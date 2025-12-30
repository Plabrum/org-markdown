local M = {}

-- Path to the fold state storage file
local storage_path = vim.fn.stdpath("state") .. "/org-markdown-folds.json"

-- In-memory cache of fold states
local cache = nil

--- Load fold states from disk
---@return table: Map of file paths to fold levels
local function load_states()
	if cache then
		return cache
	end

	local file = io.open(storage_path, "r")
	if not file then
		cache = {}
		return cache
	end

	local content = file:read("*a")
	file:close()

	if content == "" then
		cache = {}
		return cache
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok then
		vim.notify("org-markdown: Failed to load fold states, resetting", vim.log.levels.WARN)
		cache = {}
		return cache
	end

	cache = decoded
	return cache
end

--- Save fold states to disk
---@param states table: Map of file paths to fold levels
local function save_states(states)
	-- Ensure state directory exists
	local state_dir = vim.fn.stdpath("state")
	if vim.fn.isdirectory(state_dir) == 0 then
		vim.fn.mkdir(state_dir, "p")
	end

	local ok, encoded = pcall(vim.json.encode, states)
	if not ok then
		vim.notify("org-markdown: Failed to encode fold states", vim.log.levels.ERROR)
		return false
	end

	local file = io.open(storage_path, "w")
	if not file then
		vim.notify("org-markdown: Failed to open fold state file for writing", vim.log.levels.ERROR)
		return false
	end

	file:write(encoded)
	file:close()
	cache = states
	return true
end

--- Get fold level for a file
---@param filepath string: Absolute file path
---@return number|nil: Fold level, or nil if not stored
function M.get_fold_level(filepath)
	local states = load_states()
	return states[filepath]
end

--- Set fold level for a file
---@param filepath string: Absolute file path
---@param level number: Fold level to save
function M.set_fold_level(filepath, level)
	local states = load_states()
	states[filepath] = level
	save_states(states)
end

--- Clear fold level for a file
---@param filepath string: Absolute file path
function M.clear_fold_level(filepath)
	local states = load_states()
	states[filepath] = nil
	save_states(states)
end

--- Clear all stored fold states
function M.clear_all()
	save_states({})
end

return M
