local M = {}

function M.setup(opts)
	require("org_markdown.config").setup(opts or {})
	require("org_markdown.commands").register()

	-- Load sync plugins
	local sync_manager = require("org_markdown.sync.manager")
	local config = require("org_markdown.config")
	local plugin_names = { "calendar", "linear", "sheets" } -- Built-in plugins

	-- Only load plugins that are explicitly mentioned in the config
	-- The plugin's default_config and setup() will handle enabled state
	if config.sync and config.sync.plugins then
		for _, plugin_name in ipairs(plugin_names) do
			if config.sync.plugins[plugin_name] ~= nil then
				local ok, plugin = pcall(require, "org_markdown.sync.plugins." .. plugin_name)
				if ok then
					sync_manager.register_plugin(plugin)
				else
					vim.notify("Failed to load sync plugin: " .. plugin_name, vim.log.levels.WARN)
				end
			end
		end
	end

	-- Load external plugins from config
	if config.sync and config.sync.external_plugins then
		for _, plugin_name in ipairs(config.sync.external_plugins) do
			local ok, plugin = pcall(require, plugin_name)
			if ok then
				sync_manager.register_plugin(plugin)
			else
				vim.notify("Failed to load external sync plugin: " .. plugin_name, vim.log.levels.WARN)
			end
		end
	end

	-- Setup auto-sync for enabled plugins
	sync_manager.setup_auto_sync()
end

return M
