local config = require("org_markdown.config")
local async = require("org_markdown.async")
local snacks = require("snacks")

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
	snacks.picker.pick({
		source = opts.kind or "item",
		prompt = opts.prompt or "Select item",

		finder = function()
			return vim.tbl_map(function(item)
				return {
					text = opts.format_item and opts.format_item(item) or tostring(item),
					value = item,
					file = item.file, -- optional for snacks preview
				}
			end, items)
		end,

		confirm = function(picker, item)
			picker:close()
			if opts.on_confirm then
				opts.on_confirm(item.value)
			end
		end,

		format = function(item)
			if opts.format_item then
				return opts.format_item(item.value)
			end
			return { tostring(item.value), "Normal" }
		end,

		preview = function(ctx)
			if ctx.item.file then
				snacks.picker.preview.file(ctx)
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

		pickers
			.new({}, {
				prompt_title = opts.prompt or "Select item",
				finder = finders.new_table({
					results = items,
					entry_maker = function(item)
						return {
							value = item,
							display = opts.format_item and opts.format_item(item) or tostring(item),
							ordinal = tostring(item),
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(_, map_buf)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(map_buf)
						resolve(selection and selection.value or nil)
					end)
					return true
				end,
			})
			:find()
	end)
end

return M
