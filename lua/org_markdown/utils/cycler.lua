local M = {}

-- Module-level memory to track last position per feature
local memory = {}

-- Path to persistent storage file
local memory_file = vim.fn.stdpath("data") .. "/org-markdown-cycler-memory.json"

--- Load memory from disk
local function load_memory()
	local file = io.open(memory_file, "r")
	if file then
		local content = file:read("*a")
		file:close()
		local ok, decoded = pcall(vim.fn.json_decode, content)
		if ok and type(decoded) == "table" then
			memory = decoded
		end
	end
end

--- Save memory to disk
local function save_memory()
	local ok, encoded = pcall(vim.fn.json_encode, memory)
	if ok then
		local file = io.open(memory_file, "w")
		if file then
			file:write(encoded)
			file:close()
		end
	end
end

-- Load memory on module initialization
load_memory()

--- Creates a new cycler instance for a buffer
--- @param buf number: Buffer ID
--- @param win number: Window ID
--- @param opts table: Configuration options
---   - items: table[] | function() -> table[] - Array of items to cycle through OR function that returns items
---   - get_index: function(buf) -> number - Get current index from buffer state
---   - set_index: function(buf, index) - Set current index in buffer state
---   - on_cycle: function(buf, win, item, index, total) - Called when cycling to a new item
---   - get_footer: function(item, index, total) -> string - Optional footer text generator
---   - allow_single: boolean - If false, don't setup cycling when only 1 item (default: false)
---   - memory_id: string - Optional ID for remembering position across invocations (e.g., "agenda", "capture")
--- @return table: Cycler instance with methods
function M.create(buf, win, opts)
	local instance = {
		buf = buf,
		win = win,
		opts = opts,
	}

	--- Get all items (resolve function if needed)
	function instance:get_items()
		if type(self.opts.items) == "function" then
			return self.opts.items()
		else
			return self.opts.items
		end
	end

	--- Get current item
	function instance:get_current()
		local items = self:get_items()
		local index = self.opts.get_index(self.buf)
		return items[index], index, #items
	end

	--- Cycle to next/previous item
	--- @param direction number: 1 for next, -1 for previous
	function instance:cycle(direction)
		local items = self:get_items()
		local num_items = #items

		if num_items <= 1 then
			return -- Nothing to cycle
		end

		local current = self.opts.get_index(self.buf)
		local next_index

		if direction > 0 then
			-- Cycle forward
			next_index = (current % num_items) + 1
		else
			-- Cycle backward
			next_index = current == 1 and num_items or (current - 1)
		end

		self.opts.set_index(self.buf, next_index)

		-- Save to memory if memory_id is provided
		if self.opts.memory_id then
			memory[self.opts.memory_id] = next_index
			save_memory() -- Persist to disk
		end

		-- Call the on_cycle handler
		-- If it returns false, skip footer update (e.g., buffer was closed)
		local should_update_footer = true
		if self.opts.on_cycle then
			local result = self.opts.on_cycle(self.buf, self.win, items[next_index], next_index, num_items)
			if result == false then
				should_update_footer = false
			end
		end

		-- Update footer if needed
		if should_update_footer then
			self:update_footer()
		end
	end

	--- Refresh current item (without cycling)
	function instance:refresh()
		local items = self:get_items()
		local index = self.opts.get_index(self.buf)

		if self.opts.on_cycle then
			self.opts.on_cycle(self.buf, self.win, items[index], index, #items)
		end

		self:update_footer()
	end

	--- Update footer text
	function instance:update_footer()
		if not self.opts.get_footer then
			return
		end

		if not vim.api.nvim_win_is_valid(self.win) then
			return
		end

		local item, index, total = self:get_current()
		local footer = self.opts.get_footer(item, index, total)

		local win_config = vim.api.nvim_win_get_config(self.win)
		if win_config.relative and win_config.relative ~= "" then
			-- Floating window
			win_config.footer = footer
			vim.api.nvim_win_set_config(self.win, win_config)
		else
			-- Split window
			vim.wo[self.win].statusline = footer
		end
	end

	--- Setup keymaps for cycling
	function instance:setup()
		local items = self:get_items()

		-- Check allow_single option
		if #items <= 1 and not self.opts.allow_single then
			return
		end

		-- If memory_id is provided, restore last position
		if self.opts.memory_id and memory[self.opts.memory_id] then
			local saved_index = memory[self.opts.memory_id]
			-- Validate saved index is within bounds
			if saved_index >= 1 and saved_index <= #items then
				self.opts.set_index(self.buf, saved_index)
			end
		end

		-- Register ] for next
		vim.keymap.set("n", "]", function()
			self:cycle(1)
		end, { buffer = self.buf, silent = true })

		-- Register [ for previous
		vim.keymap.set("n", "[", function()
			self:cycle(-1)
		end, { buffer = self.buf, silent = true })

		-- Update footer on initial setup
		self:update_footer()
	end

	--- Cleanup keymaps
	function instance:teardown()
		-- Keymaps are automatically cleaned up when buffer is deleted
		-- This is here for explicit cleanup if needed
		if vim.api.nvim_buf_is_valid(self.buf) then
			pcall(vim.keymap.del, "n", "]", { buffer = self.buf })
			pcall(vim.keymap.del, "n", "[", { buffer = self.buf })
		end
	end

	return instance
end

--- Helper: Default index management using buffer-local variables
--- @param var_name string: Buffer variable name (e.g., 'cycler_index')
M.default_state = function(var_name)
	return {
		get_index = function(buf)
			return vim.b[buf][var_name] or 1
		end,
		set_index = function(buf, index)
			vim.b[buf][var_name] = index
		end,
	}
end

--- Get saved position for a memory_id
--- @param memory_id string: The memory ID to look up
--- @return number|nil: The saved index, or nil if not found
function M.get_memory(memory_id)
	return memory[memory_id]
end

--- Clear saved position for a memory_id
--- @param memory_id string: The memory ID to clear
function M.clear_memory(memory_id)
	memory[memory_id] = nil
	save_memory() -- Persist the change
end

return M
