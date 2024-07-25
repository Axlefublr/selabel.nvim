local m = {}

---@class PluginOpts
---An array of characters, each of which is responsible for picking that number of an option.
---For example if you provide `{ 'a', 'b', 'c' }`, you'll need to press `a` to pick the first option, `b` to pick the second, and `c` for third.
---This plugin will error out if it doesn't have enough labels to display all options given to it, so my recommendation is 15+ characters.
---(default `{ 'f', 'd', 's', 'a', 'j', 'k', 'l', ';', 'r', 'e', 'w', 'q', 'u', 'i', 'o', 'p', 'v', 'c', 'x', 'z', 'm', ',', '.', '/' }` )
---@field labels string[]
---@field label_highlight string Highlight group to color the label letters with. (default Orange)
---@field separator string Separator between the label letter and the item text (default ': ')
---@field separator_highlight string Highlight group to color the separator with (default Bold)
---@field inject boolean Replace `vim.ui.select`. (default true)
---Use the `prompt` provided to `opts` of `vim.ui.select` as the title of the floating window. (default true)
---@field enable_prompt boolean
---This plugin relies on a hack: it needs to sleep (default 1 ms) to make sure it will create the floating window before holding up the thread by asking the user for a key.
---If after executing `vim.ui.select` you can't press any keys except the labels, and yet the floating window is not there, increase this value.
---(This is not a direct sleep: it first sleeps, and then appends the key asking onto the nvim event loop. So it's not like you need to guess the perfect amount of sleep here, which is why it can be just 1)
---@field hack integer
---Either a table to provide to the `opts` of `:h nvim_open_win()`, or a function that returns that table.
---If height is not specified, it's calculated automatically from the amount of items.
---If width is not specified, it's calculated automatically from the longest item + label width.
---The function is automatically passed the count of items as the first argument, and the longest item's length + label length as the second.
---The `title` option is automatically set to the `prompt` provided to `vim.ui.select`, unless you set this plugin's `enable_prompt` option to false.
---```lua
---default = {
---  relative = 'cursor',
---  style = 'minimal',
---  border = 'double',
---  title_pos = 'center',
---  row = 1,
---  col = 1,
---}
---```
---@field win_opts table|function

---If you like one of these defaults, *don't* specify it.
---If you like all of these defaults, leave `opts = {}`.
---Don't waste the precious computer's efforts 🥺!
---@type PluginOpts
local plugin_opts = {
	-- stylua: ignore
	labels = { 'f', 'd', 's', 'a', 'j', 'k', 'l', ';', 'r', 'e', 'w', 'q', 'u', 'i', 'o', 'p', 'v', 'c', 'x', 'z', 'm', ',', '.', '/' },
	label_highlight = 'Orange',
	separator = ': ',
	separator_highlight = 'Bold',
	inject = true,
	enable_prompt = true,
	hack = 1,
	win_opts = {
		relative = 'cursor',
		style = 'minimal',
		border = 'double',
		title_pos = 'center',
		row = 1,
		col = 1,
	},
}

local function tbl_contains(table, item)
	for _, thingy in pairs(table) do
		if thingy == item then return true end
	end
	return false
end

local function tbl_slice(tbl, start, stop)
	local sliced = {}
	for index = start or 1, (stop or #tbl) do
		table.insert(sliced, tbl[index])
	end
	return sliced
end

local function tbl_index(tbl, item)
	for index, value in ipairs(tbl) do
		if value == item then return index end
	end
end

---Return the next character the user presses.
---@return string|nil character `nil` if the user pressed <Esc>.
local function char(prompt)
	---@type string|nil
	local char = vim.fn.getcharstr()
	-- In '' is the escape character (<Esc>).
	-- Not sure how to check for it without literal character magic.
	if char == '' then char = nil end
	return char
end

local LABEL_WIDTH = 1

---@param win_opts table|function
---@param items_len integer
---@param longest_len integer
local function eval_user_win_opts(win_opts, items_len, longest_len)
	if type(win_opts) == 'function' then
		return win_opts(items_len, longest_len)
	elseif type(win_opts) == 'table' then
		return vim.deepcopy(win_opts, true)
	else
		print(
			vim.inspect('selable.nvim: win_opts should be a table or a function.\nis: ' .. win_opts)
		)
	end
end

---@return table
local function build_win_opts(items_len, longest_len, prompt)
	local win_opts = eval_user_win_opts(plugin_opts.win_opts, items_len, longest_len)
	if not win_opts.width then win_opts.width = longest_len end
	if not win_opts.height then win_opts.height = items_len end
	if plugin_opts.enable_prompt and prompt then win_opts.title = prompt end
	if win_opts.title_pos and not win_opts.title then win_opts.title_pos = nil end
	return win_opts
end

---Refer to `:h vim.ui.select()`
function m.select(items, opts, on_choice)
	if #items == 0 then return end
	local opts = opts or {}
	local labels = plugin_opts.labels
	if #items > #labels then
		vim.notify('too many options (' .. #items .. ')')
		return
	end

	local valid_labels = tbl_slice(labels, 1, #items)
	local stringify = type(opts.format_item) == 'function' and opts.format_item or tostring

	local lines = {}
	local padding = #plugin_opts.separator + LABEL_WIDTH
	local longest_len = 0
	for index, item in ipairs(items) do
		local stringified = stringify(item)
		if #stringified > longest_len then longest_len = #stringified end
		table.insert(lines, labels[index] .. plugin_opts.separator .. stringified)
	end
	longest_len = longest_len + padding

	local buf = vim.api.nvim_create_buf(false, true)
	---@diagnostic disable-next-line: param-type-mismatch
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local win_opts = build_win_opts(#items, longest_len, opts.prompt)
	local window = vim.api.nvim_open_win(buf, false, win_opts)

	local namespace = vim.api.nvim_create_namespace('')
	for index = 0, #lines do
		vim.api.nvim_buf_add_highlight(buf, namespace, plugin_opts.label_highlight, index, 0, 1)
		vim.api.nvim_buf_add_highlight(
			buf,
			namespace,
			plugin_opts.separator_highlight,
			index,
			1,
			1 + #plugin_opts.separator
		)
	end

	vim.defer_fn(function()
		local picked
		repeat
			picked = char()
		until tbl_contains(valid_labels, picked) or not picked
		vim.api.nvim_win_close(window, false)
		if not picked then
			if on_choice then on_choice(nil, nil) end
			return
		end
		local index = tbl_index(valid_labels, picked)
		if on_choice then on_choice(items[index], index) end
	end, plugin_opts.hack)
end

---Array-like table of array-like tables, each one of those is two elements long.
---The first element is the "item" that is going to be displayed as the option,
---the second element is the function to execute, when that option is displayed.
---```lua
---require('selabel').select_nice({
---    { 'option one', function(item, index) vim.notify(index) end },
---    { 'another option of mine', function(item, _) vim.notify(item) end }
---}, { prompt = ' My promptie ' })
---```
---@param alternatives table[]
---@param opts table Passed to `vim.ui.select` (the second argument).
function m.select_nice(alternatives, opts)
	local items = {}
	for index, choice in ipairs(alternatives) do
		local item = choice[1]
		table.insert(items, item)
	end
	local function on_choice(item, index)
		if not item then return end
		alternatives[index][2](item, index)
	end
	m.select(items, opts, on_choice)
end

function m.setup(opts)
	plugin_opts = vim.tbl_deep_extend('force', plugin_opts, opts or {})
	if plugin_opts.inject then vim.ui.select = m.select end
end

return m
