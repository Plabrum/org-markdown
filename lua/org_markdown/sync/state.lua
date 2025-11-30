local M = {}

-- State file location
local state_dir = vim.fn.stdpath("data") .. "/org-markdown"
local state_file = state_dir .. "/sync-state.json"

-- ============================================================================
-- STATE DIRECTORY MANAGEMENT
-- ============================================================================

--- Ensure state directory exists
function M.ensure_state_dir()
	if vim.fn.isdirectory(state_dir) == 0 then
		vim.fn.mkdir(state_dir, "p")
	end
end

-- ============================================================================
-- INTERNAL STATE MANAGEMENT
-- ============================================================================

--- Load all state (internal)
--- @return table all_state
local function load_all_state()
	M.ensure_state_dir()

	if vim.fn.filereadable(state_file) == 0 then
		return {}
	end

	local content = vim.fn.readfile(state_file)
	if #content == 0 then
		return {}
	end

	local ok, state = pcall(vim.json.decode, table.concat(content, "\n"))
	if not ok then
		vim.notify("Failed to parse sync state: " .. tostring(state), vim.log.levels.WARN)
		return {}
	end

	return state
end

--- Save all state (internal)
--- @param all_state table State table to save
local function save_all_state(all_state)
	M.ensure_state_dir()

	local json = vim.json.encode(all_state)

	-- Atomic write using temp file
	local temp = state_file .. ".tmp"
	vim.fn.writefile(vim.split(json, "\n"), temp)

	local ok, err = pcall(vim.uv.fs_rename, temp, state_file)
	if not ok then
		-- Clean up temp file on error
		vim.uv.fs_unlink(temp)
		vim.notify("Failed to save sync state: " .. tostring(err), vim.log.levels.ERROR)
	end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Load state for specific plugin
--- @param plugin_name string Plugin name
--- @return table plugin_state Plugin state or empty table if none exists
function M.load_plugin_state(plugin_name)
	local all_state = load_all_state()
	return all_state[plugin_name] or {}
end

--- Save state for specific plugin
--- @param plugin_name string Plugin name
--- @param state table Plugin state to save
function M.save_plugin_state(plugin_name, state)
	local all_state = load_all_state()
	all_state[plugin_name] = state
	save_all_state(all_state)
end

--- Clear state for specific plugin
--- @param plugin_name string Plugin name
function M.clear_plugin_state(plugin_name)
	local all_state = load_all_state()
	all_state[plugin_name] = nil
	save_all_state(all_state)
end

--- Get all plugin states (for debugging)
--- @return table all_states
function M.get_all_states()
	return load_all_state()
end

--- Get state file path (for debugging)
--- @return string state_file_path
function M.get_state_file_path()
	return state_file
end

return M
