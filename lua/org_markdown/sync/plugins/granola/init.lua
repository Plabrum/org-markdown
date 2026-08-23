-- Granola: the first ingestion source.
--
-- Unlike the mirroring plugins (calendar, linear), this one runs in append
-- mode: each sync reads Granola's local cache, pulls the action items out of
-- the meetings that have finished, and appends the ones the log doesn't
-- already carry. Entries that landed on an earlier sync are never rewritten --
-- the user, and later the promotion sweep, edit them in place.
--
-- An item's text is ingested verbatim; where it came from (meeting title and
-- date) goes in the body, so an entry still names its origin after it has been
-- promoted out of the log.

local config = require("org_markdown.config")
local datetime = require("org_markdown.utils.datetime")
local platform = require("org_markdown.platform")
local cache = require("org_markdown.sync.plugins.granola.cache")

local M = {
	name = "granola",
	description = "Ingest action items from Granola meetings",
	sync_file = "~/org/sources/granola.md",
	mode = "append",

	default_config = {
		enabled = false,
		sync_file = "~/org/sources/granola.md",
		cache_file = "~/Library/Application Support/Granola/cache-v3.json",

		-- Headings whose bullets are action items. Granola's generated summary
		-- lists them under one of these, as plain bullets.
		action_item_headings = { "action items", "next steps", "follow ups", "follow-ups" },

		-- Only look back this far, so the first sync doesn't ingest every
		-- meeting ever recorded. Set to 0 for no limit.
		lookback_days = 30,

		status = "TODO",
		tags = { "granola" },
		heading_level = 1,
		auto_sync = false,
		auto_sync_interval = 1800, -- 30 minutes
	},

	supports_auto_sync = true,
	command_name = "MarkdownSyncGranola",
	keymap = "<leader>og",
}

--- Turn one action item into an ingestion entry. The key is the meeting id
--- plus the item text, so re-reading the same meeting never ingests it twice
--- while an item added to the notes later still lands. An item ticked off in
--- Granola is reported DONE, which completes whatever was promoted from it.
--- @param meeting table Meeting from `cache.meetings()`
--- @param item table Action item from `cache.action_items()`
--- @param plugin_config table Plugin configuration
--- @return table item
function M.to_item(meeting, item, plugin_config)
	local origin = { string.format("**Meeting:** %s", meeting.title) }
	if meeting.date then
		table.insert(origin, string.format("**Date:** %s", datetime.to_org_string(meeting.date)))
	end

	return {
		title = item.text,
		status = item.done and "DONE" or plugin_config.status,
		tags = plugin_config.tags,
		body = table.concat(origin, "\n"),
		key = string.format("granola:%s::%s", meeting.id, item.text),
	}
end

--- Pull action items from every finished meeting in the cache.
--- @return table|nil, string|nil Result with items and stats, error message
function M.pull()
	local plugin_config = config.sync.plugins.granola or {}

	local state, err = cache.load(platform.path.expand(plugin_config.cache_file))
	if not state then
		return nil, err
	end

	local now = os.time()
	local lookback = plugin_config.lookback_days or 0
	local meetings = cache.meetings(state, {
		now = now,
		since = lookback > 0 and (now - lookback * 86400) or nil,
	})

	local items = {}
	for _, meeting in ipairs(meetings) do
		for _, item in ipairs(cache.action_items(meeting.lines, plugin_config.action_item_headings or {})) do
			table.insert(items, M.to_item(meeting, item, plugin_config))
		end
	end

	return {
		items = items,
		stats = { count = #items, source = "Granola", meetings = #meetings },
	}
end

return M
