local scandir = require("plenary.scandir")
local previewers = require("telescope.previewers")
local Path = require("plenary.path")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorters = require("telescope.sorters")

local function getDirectoryName(path)
	-- Pattern explanation:
	-- .*/ matches everything up to the last slash
	-- ([^/]+) captures the directory name after the last slash
	-- /?$ optionally matches a trailing slash, if present
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

-- Additional requires

local function createFileIfNotExists(directory, input)
	local filename = slugify(input) .. ".md"
	local filePath = Path:new(directory, filename):absolute()

	if Path:new(filePath):exists() then
		print("File already exists. Aborting.")
		return false
	else
		local header = "# " .. input
		Path:new(filePath):write(header, "w")
		print("Note created: " .. filePath)
		return true
	end
end

local function fuzzyFindFilesAndCreate(directory)
	local input = nil -- Variable to capture the user's input

	-- Custom finder that prepends the search query to the list of files
	local finder = setmetatable({}, {
		__call = function(_, prompt)
			if not input or input ~= prompt then
				input = prompt -- Update the captured input with the current prompt
				local files = {}
				if prompt ~= "" then
					-- Prepend the search query as a 'Create New File: <query>' option
					table.insert(files, "Create New File: " .. prompt)
				end
				-- List files in the directory and append to the list
				for _, file in ipairs(scandir.scan_dir(directory, { hidden = true, add_dirs = true })) do
					table.insert(files, file)
				end
				return files
			end
		end,
	})

	pickers
		.new({}, {
			prompt_title = "Find File or Create New",
			finder = finders.new_dynamic({
				fn = finder,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function(bufnr)
					local selection = action_state.get_selected_entry()
					actions.close(bufnr)
					-- Handle selection or input for file creation
					if selection.value:match("^Create New File:") then
						local query = selection.value:gsub("Create New File: ", "")
						if createFileIfNotExists(directory, query) then
							vim.cmd(":edit " .. directory .. "/" .. slugify(query) .. ".md")
						end
					else
						vim.cmd(":edit " .. selection.value)
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