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
	local filename = slugify(input) .. ".md"
	local filePath = Path:new(directory, filename):absolute()

	if Path:new(filePath):exists() then
		print("File already exists. Aborting.")
		return filePath, false
	else
		local header = "# " .. input
		Path:new(filePath):write(header, "w")
		print("Note created: " .. filePath)
		return filePath, true
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
	local input = nil

	local finder = setmetatable({}, {
		__call = function(_, prompt)
			if not input or input ~= prompt then
				input = prompt
				local files = {}
				if prompt ~= "" then
					table.insert(files, "Create New File: " .. prompt)
				end
				for _, file in ipairs(vim.fn.readdir(directory)) do
					table.insert(files, file)
				end
				return files
			end
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
					actions.close(prompt_bufnr)

					-- Check if the selection is for creating a new file and adjust `input` accordingly
					local createNewFilePrefix = "Create New File: "
					if selection.value:match("^" .. createNewFilePrefix) then
						input = selection.value:sub(#createNewFilePrefix + 1)
					else
						input = selection.value
					end

					local filepath, wasCreated = createFileIfNotExists(directory, input)
					if wasCreated then
						local templateName = getTemplateForNewFile(filepath)
						if templateName then
							local bufnr = vim.fn.bufadd(filepath)
							vim.api.nvim_buf_call(bufnr, function()
								vim.cmd("ObsidianTemplate " .. templateName)
							end)
						else
							print("No matching template found for the new file.")
						end
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
