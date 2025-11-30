local config = require("org_markdown.config")
local async = require("org_markdown.utils.async")

local M = {}

---@async
---@param items table
---@param opts table: { prompt, format_item?, preview?, kind?, on_select? (deprecated) }
---@return any selected item (awaitable)
function M.pick(items, opts)
	opts = opts or {}
	local picker = config.picker or "telescope"

	if picker == "snacks" then
		M._pick_snacks(items, opts)
	else
		M._pick_telescope(items, opts)
	end
end

function M._pick_snacks(items, opts)
	local Snacks = require("snacks")
	opts = opts or {}

	local function row_from(item)
		-- decide what the matcher should search
		local text = item.text
			or (type(item.value) == "string" and item.value)
			or item.file
			or item.name
			or item.label
			or item.title
			or tostring(item)
		if type(text) ~= "string" then
			text = tostring(text)
		end
		return { text = text, value = item, file = item.file }
	end

	local rows = {}
	for _, it in ipairs(items) do
		rows[#rows + 1] = row_from(it)
	end

	return Snacks.picker.pick({
		title = opts.prompt or "Select item",

		-- Give the picker a static list; fuzzy matching happens on `text`.
		items = rows,

		-- purely visual
		format = function(entry)
			if opts.format_item then
				local ok, out = pcall(opts.format_item, entry.value)
				if ok and out ~= nil then
					return out
				end
			end
			return entry.text
		end,

		-- be defensive: entry can be nil
		confirm = function(picker, entry)
			if not entry then
				if opts.debug then
					print("[snacks-pick debug] confirm: nil entry")
				end
				picker:close()
				return
			end
			picker:close()
			if opts.on_confirm then
				pcall(opts.on_confirm, entry.value)
			end
		end,

		preview = function(ctx)
			if ctx.item and ctx.item.file then
				Snacks.picker.preview.file(ctx)
			else
				ctx.preview:reset()
				ctx.preview:set_title("No preview")
			end
		end,
	})
end

-- Telescope picker: promise-style
function M._pick_telescope(items, opts)
	return async.promise(function(resolve, _)
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		-- Helper to convert highlight group table to plain string
		local function format_to_string(formatted)
			if type(formatted) == "string" then
				return formatted
			elseif type(formatted) == "table" then
				-- Extract text from highlight group format: { { "text", "hl" }, ... }
				local parts = {}
				for _, part in ipairs(formatted) do
					if type(part) == "table" and part[1] then
						table.insert(parts, part[1])
					elseif type(part) == "string" then
						table.insert(parts, part)
					end
				end
				return table.concat(parts, "")
			end
			return tostring(formatted)
		end

		pickers
			.new({}, {
				prompt_title = opts.prompt or "Select item",
				finder = finders.new_table({
					results = items,
					entry_maker = function(item)
						-- Build ordinal for fuzzy matching
						local ordinal_text = item.text
							or item.name
							or item.label
							or item.title
							or (item.file and vim.fn.fnamemodify(item.file, ":t"))
							or tostring(item)

						-- Handle format_item return value
						local display_value
						if opts.format_item then
							local formatted = opts.format_item(item)
							-- Convert to plain string for telescope (handles highlight group tables)
							display_value = format_to_string(formatted)
						else
							display_value = ordinal_text
						end

						return {
							value = item,
							display = display_value,
							ordinal = ordinal_text,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection and selection.value then
							if opts.on_confirm then
								opts.on_confirm(selection.value)
							end
							resolve(selection.value)
						else
							resolve(nil)
						end
					end)
					return true
				end,
			})
			:find()
	end)
end

return M
