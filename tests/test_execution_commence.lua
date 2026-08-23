local MiniTest = require("mini.test")
local helpers = require("helpers")

-- Covers commencing a focus block: which tasks are eligible, the narrowing to
-- the top available priority tier, and the chosen task being driven to STARTED.

local commence = require("org_markdown.execution.commence")
local config = require("org_markdown.config")
local machine = require("org_markdown.execution.machine")
local state = require("org_markdown.execution.state")

local workspace = nil

--- Offer a workspace of `{ [relative path] = lines }` as the only refile path,
--- with a fresh execution log.
local function with_workspace(files)
	workspace = helpers.create_temp_workspace(files)
	config.setup({ execution = { log_file = vim.fn.tempname() .. ".log" } })
	config.refile_paths = { workspace }
	return workspace
end

--- The titles of a list of agenda items, in order.
local function titles(items)
	local out = {}
	for _, item in ipairs(items) do
		table.insert(out, item.title)
	end
	return out
end

local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			if workspace then
				helpers.cleanup_temp(workspace)
				workspace = nil
			end
			config.setup({})
		end,
	},
})

-- Eligibility ----------------------------------------------------------------

T["eligible - drops finished tasks"] = function()
	with_workspace({
		["work.md"] = {
			"# TODO Write docs",
			"",
			"# DONE Ship it",
			"",
			"# CANCELLED Never mind",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Write docs" })
end

T["eligible - drops a task the log has already taken to DONE"] = function()
	local root = with_workspace({
		["work.md"] = {
			"# TODO Write docs",
			"",
			"# TODO Ship it",
			"",
		},
	})

	machine.transition(root .. "/work.md::Ship it", machine.STARTED)
	machine.transition(root .. "/work.md::Ship it", machine.DONE)

	MiniTest.expect.equality(titles(commence.eligible()), { "Write docs" })
end

T["eligible - drops tasks waiting on something else"] = function()
	with_workspace({
		["work.md"] = {
			"# TODO Write docs",
			"",
			"# BLOCKED Deploy",
			"",
			"# WAITING Review",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Write docs" })
end

T["eligible - drops what the source reports done"] = function()
	with_workspace({ ["work.md"] = { "# TODO Write docs", "", "# TODO Ship it", "" } })

	local original = commence.is_externally_done
	commence.is_externally_done = function(item)
		return item.title == "Ship it"
	end
	local eligible = titles(commence.eligible())
	commence.is_externally_done = original

	MiniTest.expect.equality(eligible, { "Write docs" })
end

T["eligible - counts sub-tasks as tasks"] = function()
	with_workspace({
		["work.md"] = {
			"# Project",
			"",
			"## TODO Write docs",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Write docs" })
end

-- The top tier ---------------------------------------------------------------

T["eligible - offers only the highest priority tier that has anything in it"] = function()
	with_workspace({
		["work.md"] = {
			"# TODO [#B] Write docs",
			"",
			"# TODO [#A] Fix the build",
			"",
			"# TODO [#C] Tidy up",
			"",
			"# TODO Whenever",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Fix the build" })
end

T["eligible - the top tier is whatever is left once the better ones are done"] = function()
	with_workspace({
		["work.md"] = {
			"# DONE [#A] Fix the build",
			"",
			"# TODO [#B] Write docs",
			"",
			"# TODO [#C] Tidy up",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Write docs" })
end

T["eligible - unprioritized tasks are their own, lowest tier"] = function()
	with_workspace({
		["work.md"] = {
			"# TODO Whenever <2026-08-24 Mon>",
			"",
			"# TODO Sooner <2026-08-23 Sun>",
			"",
		},
	})

	MiniTest.expect.equality(titles(commence.eligible()), { "Sooner", "Whenever" })
end

T["eligible - nothing eligible is an empty list, not an error"] = function()
	with_workspace({ ["work.md"] = { "# DONE Ship it", "" } })
	MiniTest.expect.equality(commence.eligible(), {})
end

-- Commencing -----------------------------------------------------------------

T["commence - the chosen task becomes STARTED"] = function()
	local root = with_workspace({ ["work.md"] = { "# TODO Write docs", "" } })

	local task = commence.eligible()[1]
	local events, err = commence.commence(task)

	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(#events, 1)
	MiniTest.expect.equality(state.state_of(root .. "/work.md::Write docs"), machine.STARTED)
	MiniTest.expect.equality(state.started_task(), root .. "/work.md::Write docs")
end

T["commence - pauses whatever the previous block left running"] = function()
	local root = with_workspace({ ["work.md"] = { "# TODO Write docs", "", "# TODO Fix the build", "" } })

	machine.transition(root .. "/work.md::Fix the build", machine.STARTED)

	local events = commence.commence(root .. "/work.md::Write docs")
	MiniTest.expect.equality(#events, 2)
	MiniTest.expect.equality(state.state_of(root .. "/work.md::Fix the build"), machine.PAUSED)
	MiniTest.expect.equality(state.started_task(), root .. "/work.md::Write docs")
end

-- The block being commenced --------------------------------------------------

T["block_at - the block covering a moment, and none when there is none"] = function()
	with_workspace({
		["calendar.md"] = {
			"# Morning <2026-08-23 Sun 09:00-11:00> :focus:",
			"",
			"# Afternoon <2026-08-23 Sun 13:00-15:00> :focus:",
			"",
			"# Kickoff <2026-08-23 Sun 09:30-10:00>",
			"",
		},
	})

	local block = commence.block_at({ date = "2026-08-23", time = "09:30" })
	MiniTest.expect.equality(block.title, "Morning")

	MiniTest.expect.equality(commence.block_at({ date = "2026-08-23", time = "12:00" }), nil)
	MiniTest.expect.equality(commence.block_at({ date = "2026-08-24", time = "09:30" }), nil)
end

T["block_at - a block with no end runs to the end of its day"] = function()
	with_workspace({ ["calendar.md"] = { "# Deep work <2026-08-23 Sun 09:00> :focus:", "" } })

	local block = commence.block_at({ date = "2026-08-23", time = "18:00" })
	MiniTest.expect.equality(block.title, "Deep work")
end

return T
