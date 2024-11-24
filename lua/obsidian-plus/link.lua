local M = {}

local scandir = require("plenary.scandir")
local previewers = require("telescope.previewers")
local Path = require("plenary.path")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorters = require("telescope.sorters")

local user_configs = {
	template_mappings = {},
}

function M.setUserConfigs(configs)
	user_configs = configs
end

local function getDirectoryName(path)
	local name = path:match(".*/([^/]+)/?$")
	return name
end

local function slugify(title)
	return title:lower():gsub("%s", "-"):gsub("[^%w%-]", "")
end

local function getDirectories(baseDir)
	local dirs = {}
	scandir.scan_dir(baseDir, {
		hidden = true,
		add_dirs = true,
		depth = 1,
		on_insert = function(entry, typ)
			if typ == "directory" then
				table.insert(dirs, entry)
			end
		end,
	})
	return dirs
end

local function createFileIfNotExists(directory, input)
	local slug = slugify(input)
	local filename = slug .. ".md"
	local filePath = Path:new(directory, filename):absolute()

	if Path:new(filePath):exists() then
		print("File already exists. Aborting.")
		return filePath, false, slug -- Notice we return slug here as well
	else
		local header = "---\n" .. "aliases:\n" .. "- " .. input .. "\n" .. "---\n" .. "# " .. input .. "\n"

		Path:new(filePath):write(header, "w")
		print("Note created: " .. filePath)
		return filePath, true, slug -- And here
	end
end

local function getTemplateForNewFile(filePath)
	for pattern, templatePath in pairs(user_configs.template_mappings) do
		local luaPattern = pattern:gsub("%*", ".+") -- Convert glob pattern to Lua pattern
		if filePath:match(luaPattern) then
			-- Extract the filename from the templatePath
			local filename = templatePath:match("([^/]+)$")
			return filename
		end
	end
	return nil -- No matching template
end

local function fuzzyFindFilesAndCreate(directory)
	local origBuf = vim.api.nvim_get_current_buf()
	local origCursorPos = vim.api.nvim_win_get_cursor(0)

	local finder = setmetatable({}, {
		__call = function(_, prompt)
			local files = {}
			-- Ensure prompt is never nil
			prompt = prompt or ""
			if prompt ~= "" then
				table.insert(files, "Create New File: " .. prompt)
			end
			local readdirFiles = vim.fn.readdir(directory)
			for _, file in ipairs(readdirFiles) do
				table.insert(files, file)
			end
			return files
		end,
	})

	pickers
		.new({}, {
			prompt_title = "Find File or Create New",
			finder = finders.new_dynamic({ fn = finder }),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr) -- Ensure actions.close is called before modifying the buffer or cursor

					if selection.value:match("^Create New File: ") then
						local input = selection.value:sub(#"Create New File: " + 1)
						local filepath, wasCreated, slug = createFileIfNotExists(directory, input)
						if wasCreated then
							vim.api.nvim_buf_set_text(
								origBuf,
								origCursorPos[1] - 1,
								origCursorPos[2],
								origCursorPos[1] - 1,
								origCursorPos[2],
								{ "[[" .. slug .. "|" .. input .. "]] " }
							)
							vim.api.nvim_win_set_cursor(0, { origCursorPos[1], origCursorPos[2] + #slug + #input + 4 }) -- Cursor after the final ']' with a space
							vim.cmd("split " .. filepath .. " | normal G")
						end
					else
						-- Handle existing file selection
						local slug = vim.fn.fnamemodify(selection.value, ":t:r")
						vim.api.nvim_buf_set_text(
							origBuf,
							origCursorPos[1] - 1,
							origCursorPos[2],
							origCursorPos[1] - 1,
							origCursorPos[2],
							{ "[[" .. slug .. "]]" }
						)
						vim.api.nvim_win_set_cursor(0, { origCursorPos[1], origCursorPos[2] + #slug + 3 }) -- Cursor immediately after the first ']'
					end
				end)
				return true
			end,
		})
		:find()
end

function M.selectDirectoryAndCreateNote()
	local notesDir = os.getenv("HOME") .. "/vaults/personal/notes"
	local dirs = getDirectories(notesDir)

	pickers
		.new({}, {
			prompt_title = "Select Directory",
			finder = finders.new_table({
				results = dirs,
				entry_maker = function(entry)
					return {
						value = entry,
						display = getDirectoryName(entry),
						ordinal = entry,
					}
				end,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			previewer = previewers.new_termopen_previewer({
				get_command = function(entry)
					return { "ls", "-A", entry.value }
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					fuzzyFindFilesAndCreate(selection.value)
				end)
				return true
			end,
		})
		:find()
end

return M
