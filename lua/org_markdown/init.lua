local M = {}

function M.setup(opts)
	require("org_markdown.config").setup(opts or {})
	require("org_markdown.commands").register()

	-- Load sync plugins
	local sync_manager = require("org_markdown.sync.manager")
	local plugin_names = { "calendar" } -- Built-in plugins

	for _, plugin_name in ipairs(plugin_names) do
		local ok, plugin = pcall(require, "org_markdown.sync.plugins." .. plugin_name)
		if ok then
			sync_manager.register_plugin(plugin)
		else
			vim.notify("Failed to load sync plugin: " .. plugin_name, vim.log.levels.WARN)
		end
	end

	-- Load external plugins from config
	local config = require("org_markdown.config")
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
