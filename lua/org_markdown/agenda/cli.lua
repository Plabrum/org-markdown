-- In-editor bridge to the standalone `org` CLI.
--
-- The agenda no longer computes anything in-process: it shells out to
-- `bin/org agenda --view <id>`, which runs the shared vim-free pipeline under
-- luajit and prints the view as JSON, then decodes that back into the groups
-- the in-editor renderer consumes. Config parity is achieved by exporting the
-- live resolved config to a temp file and pointing the CLI at it via
-- `$ORG_MARKDOWN_CONFIG` (see `utils.config_export` and `config.ENV_CONFIG`).

local config = require("org_markdown.config")
local config_export = require("org_markdown.utils.config_export")

local M = {}

--- Absolute path to `bin/org`, derived from this module's location so it works
--- regardless of where the plugin is installed (no hardcoded path).
--- This file is `<root>/lua/org_markdown/agenda/cli.lua`, so four `:h` climbs
--- (cli.lua -> agenda -> org_markdown -> lua -> <root>) reach the plugin root.
---@return string
local function find_org_bin()
	local source = debug.getinfo(1, "S").source
	local this_file = source:sub(1, 1) == "@" and source:sub(2) or source
	local root = vim.fn.fnamemodify(this_file, ":h:h:h:h")
	return root .. "/bin/org"
end

--- Run `org agenda --view <view_id>` and return its decoded groups.
--- The live config is exported to a temp file so the CLI reproduces the
--- in-editor items exactly; the file is removed before returning.
---@param view_id string
---@return table[]|nil groups, string|nil err
function M.compute_view(view_id)
	local bin = find_org_bin()
	if vim.fn.executable(bin) == 0 then
		return nil, "org CLI not found or not executable at " .. bin
	end

	local cfg_path, export_err = config_export.write_temp()
	if not cfg_path then
		return nil, export_err
	end

	local ok, result = pcall(function()
		return vim
			.system({ bin, "agenda", "--view", view_id }, {
				text = true,
				env = { [config.ENV_CONFIG] = cfg_path },
			})
			:wait()
	end)

	os.remove(cfg_path)

	if not ok then
		return nil, "failed to run org CLI: " .. tostring(result)
	end
	if result.code ~= 0 then
		local stderr = (result.stderr and result.stderr ~= "") and result.stderr or "(no stderr)"
		return nil, string.format("org agenda exited %d: %s", result.code, stderr)
	end

	local decoded_ok, decoded = pcall(vim.json.decode, result.stdout or "")
	if not decoded_ok or type(decoded) ~= "table" then
		return nil, "could not decode agenda JSON: " .. tostring(decoded)
	end

	return decoded.groups or {}, nil
end

return M
