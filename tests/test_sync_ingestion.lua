local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local sync_manager = require("org_markdown.sync.manager")
local utils = require("org_markdown.utils.utils")

-- =========================================================================
-- Test utilities
-- =========================================================================

local TEST_DIR = "/tmp/org-markdown-test-ingestion"

local function cleanup_test_files()
	vim.fn.delete(TEST_DIR, "rf")
end

--- Register a throwaway ingestion-mode plugin that returns a fixed item list
--- on pull(), and run a sync for it. Each test uses a distinct plugin name
--- so registry/config state from prior tests can't bleed in.
local function sync_ingestion_items(name, items)
	local sync_file = TEST_DIR .. "/" .. name .. ".md"

	sync_manager.register_plugin({
		name = name,
		description = "Test Ingestion Plugin",
		sync_file = sync_file,
		mode = "ingestion",
		default_config = {
			enabled = true,
		},
		pull = function()
			return {
				items = items,
				stats = { count = #items },
			}
		end,
	})

	-- pull() here doesn't await anything, so async.run's coroutine completes
	-- synchronously within this call - the file write has already happened
	-- by the time sync_plugin() returns.
	sync_manager.sync_plugin(name)

	return sync_file
end

-- =========================================================================
-- Basic append behavior
-- =========================================================================

T["ingestion mode - appends items to a fresh file"] = function()
	vim.fn.mkdir(TEST_DIR, "p")

	local sync_file = sync_ingestion_items("ingest_fresh", {
		{ title = "Action item 1", id = "meeting-1-item-1", body = "From meeting X" },
	})

	local lines = utils.read_lines(sync_file)
	local found_heading, found_id = false, false
	for _, line in ipairs(lines) do
		if line:match("Action item 1") then
			found_heading = true
		end
		if line == "<!-- id: meeting-1-item-1 -->" then
			found_id = true
		end
	end

	MiniTest.expect.equality(found_heading, true)
	MiniTest.expect.equality(found_id, true)

	cleanup_test_files()
end

T["ingestion mode - re-running with the same items does not duplicate"] = function()
	vim.fn.mkdir(TEST_DIR, "p")

	local items = {
		{ title = "Action item 1", id = "meeting-2-item-1", body = "From meeting Y" },
	}

	local sync_file = sync_ingestion_items("ingest_repeat", items)
	local after_first = utils.read_lines(sync_file)

	sync_ingestion_items("ingest_repeat", items)
	local after_second = utils.read_lines(sync_file)

	MiniTest.expect.equality(after_second, after_first)

	-- Only one copy of the id marker should be present
	local count = 0
	for _, line in ipairs(after_second) do
		if line == "<!-- id: meeting-2-item-1 -->" then
			count = count + 1
		end
	end
	MiniTest.expect.equality(count, 1)

	cleanup_test_files()
end

T["ingestion mode - new items are appended below prior entries, unchanged"] = function()
	vim.fn.mkdir(TEST_DIR, "p")

	local item_a = { title = "Action item A", id = "meeting-3-item-a", body = "From meeting Z" }
	local item_b = { title = "Action item B", id = "meeting-3-item-b", body = "From meeting Z" }

	local sync_file = sync_ingestion_items("ingest_mixed", { item_a })
	local after_first = utils.read_lines(sync_file)

	-- Second sync sees item_a again (already present) plus new item_b
	sync_ingestion_items("ingest_mixed", { item_a, item_b })
	local after_second = utils.read_lines(sync_file)

	-- Every line from the first sync must still be present, in order, at the start
	for i, line in ipairs(after_first) do
		MiniTest.expect.equality(after_second[i], line)
	end

	-- And item_b's marker should now exist somewhere after that
	local found_b = false
	for i = #after_first + 1, #after_second do
		if after_second[i] == "<!-- id: meeting-3-item-b -->" then
			found_b = true
		end
	end
	MiniTest.expect.equality(found_b, true)

	cleanup_test_files()
end

T["ingestion mode - empty item list leaves the file untouched"] = function()
	vim.fn.mkdir(TEST_DIR, "p")
	local sync_file = TEST_DIR .. "/ingest_empty.md"

	sync_ingestion_items("ingest_empty", {})

	-- append_sync_file must not create a file when there's nothing new to add
	MiniTest.expect.equality(vim.fn.filereadable(sync_file), 0)

	cleanup_test_files()
end

-- =========================================================================
-- Stable key derivation (M.item_key)
-- =========================================================================

T["item_key - uses explicit id when provided"] = function()
	local item = { title = "Anything", id = "explicit-123" }
	MiniTest.expect.equality(sync_manager.item_key(item), "explicit-123")
end

T["item_key - is deterministic across calls for equivalent items without an id"] = function()
	local item1 = { title = "Buy milk", body = "from the store" }
	local item2 = { title = "Buy milk", body = "from the store" }

	MiniTest.expect.equality(sync_manager.item_key(item1), sync_manager.item_key(item2))
end

T["item_key - differs for items with different content"] = function()
	local item1 = { title = "Buy milk" }
	local item2 = { title = "Buy eggs" }

	MiniTest.expect.equality(sync_manager.item_key(item1) == sync_manager.item_key(item2), false)
end

return T
