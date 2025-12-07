local M = {}

-- Cache for loaded .env files
local env_cache = {}
local env_loaded = false

--- Load environment variables from .env file
--- @param filepath string|nil Path to .env file (defaults to ~/.env)
--- @return boolean Success
function M.load_env_file(filepath)
	filepath = filepath or vim.fn.expand("~/.env")

	-- Check cache
	if env_cache[filepath] then
		return true
	end

	local f = io.open(filepath, "r")
	if not f then
		return false
	end

	for line in f:lines() do
		-- Skip empty lines and comments
		if line:match("%S") and not line:match("^%s*#") then
			-- Parse KEY=VALUE or KEY="VALUE" or KEY='VALUE'
			local key, value = line:match("^%s*([%w_]+)%s*=%s*(.*)%s*$")
			if key and value then
				-- Remove quotes if present
				value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
				-- Set environment variable
				vim.fn.setenv(key, value)
			end
		end
	end

	f:close()
	env_cache[filepath] = true
	return true
end

--- Auto-load .env files from common locations
local function auto_load_env()
	if env_loaded then
		return
	end
	env_loaded = true

	-- Try loading from common locations (in order of priority)
	local locations = {
		vim.fn.stdpath("config") .. "/.env", -- Neovim config dir (e.g., ~/.config/nvim/.env)
		vim.fn.getcwd() .. "/.env", -- Current working directory
		vim.fn.expand("~/.env"), -- Home directory fallback
	}

	for _, location in ipairs(locations) do
		if M.load_env_file(location) then
			-- Successfully loaded, don't try other locations
			return
		end
	end
end

--- Resolve a secret from various sources
--- Supports:
---   - env:VAR_NAME - Read from environment variable (auto-loads .env files)
---   - cmd:command - Execute shell command and use output
---   - file:/path/to/file - Read from file
---   - Plain string - Return as-is
--- @param value string|nil Secret reference or plain value
--- @return string|nil Resolved secret value
function M.resolve(value)
	if not value or value == "" then
		return nil
	end

	-- Auto-load .env file on first use
	auto_load_env()

	-- Environment variable: env:VAR_NAME
	local env_var = value:match("^env:(.+)$")
	if env_var then
		local secret = os.getenv(env_var)
		if not secret or secret == "" then
			vim.notify(string.format("Environment variable '%s' not set or empty", env_var), vim.log.levels.WARN)
			return nil
		end
		return secret
	end

	-- Shell command: cmd:command
	local cmd = value:match("^cmd:(.+)$")
	if cmd then
		local output = vim.fn.system(cmd)
		if vim.v.shell_error ~= 0 then
			vim.notify(string.format("Command failed: %s (exit code: %d)", cmd, vim.v.shell_error), vim.log.levels.WARN)
			return nil
		end
		-- Trim whitespace
		return output:match("^%s*(.-)%s*$")
	end

	-- File path: file:/path/to/file
	local filepath = value:match("^file:(.+)$")
	if filepath then
		filepath = vim.fn.expand(filepath) -- Expand ~ and env vars
		local f = io.open(filepath, "r")
		if not f then
			vim.notify(string.format("Could not read secret from file: %s", filepath), vim.log.levels.WARN)
			return nil
		end
		local content = f:read("*all")
		f:close()
		-- Trim whitespace
		return content:match("^%s*(.-)%s*$")
	end

	-- Plain string - return as-is
	return value
end

--- Resolve multiple config fields that may contain secret references
--- @param config table Config table to process
--- @param fields table Array of field names that may contain secrets
--- @return table Config table with resolved secrets
function M.resolve_config(config, fields)
	for _, field in ipairs(fields) do
		if config[field] then
			config[field] = M.resolve(config[field])
		end
	end
	return config
end

return M
