local scandir = require("plenary.scandir")
local previewers = require("telescope.previewers")
local Path = require("plenary.path")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorters = require("telescope.sorters")

local function getCursorPos()
	return vim.api.nvim_win_get_cursor(0) -- Returns a tuple {row, col}
end

local function getCurrentBuf()
	return vim.api.nvim_get_current_buf()
end

local previewer = previewers.new_buffer_previewer({
	define_preview = function(self, entry)
		-- Check if the entry is the "Create New File" option
		if entry.value:match("^Create New File:") then
			-- Set preview to empty for "Create New File" option
			return
		else
			-- Use the default previewer for files
			previewers.buffer_previewer_maker(entry.value, self.state.bufnr, {
				bufname = self.state.bufname,
				winid = self.state.winid,
			})
		end
	end,
})

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

-- Assuming slugify and createFileIfNotExists functions are defined elsewhere

local function fuzzyFindFilesAndCreate(directory)
	local origBuf = vim.api.nvim_get_current_buf() -- Capture the original buffer
	local origCursorPos = vim.api.nvim_win_get_cursor(0)
	local input = nil -- Variable to capture the user's input

	-- Custom finder
	local finder = setmetatable({}, {
		__call = function(_, prompt)
			if not input or input ~= prompt then
				input = prompt -- Update the captured input
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

	require("telescope.pickers")
		.new({}, {
			prompt_title = "Find File or Create New",
			finder = require("telescope.finders").new_dynamic({
				fn = finder,
			}),
			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				require("telescope.actions").select_default:replace(function()
					local selection = require("telescope.actions.state").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)

					local filepath, queryWasUsedForCreation = "", false
					if selection.value:match("^Create New File:") then
						local query = selection.value:gsub("Create New File: ", "")
						filepath = directory .. "/" .. slugify(query) .. ".md"
						queryWasUsedForCreation = not vim.loop.fs_stat(filepath)
						createFileIfNotExists(directory, query)
						vim.cmd("write") -- Save the newly created file
					else
						filepath = directory .. "/" .. selection.value
					end

					vim.api.nvim_set_current_buf(origBuf)
					vim.api.nvim_win_set_cursor(0, origCursorPos)
					local row, col = unpack(origCursorPos)

					local filenameWithoutExt = filepath:match("([^/]+)%.%w+$")
					if not queryWasUsedForCreation then
						-- Insert format: [[fileNameWithoutExt]]
						linkFormat = "[[" .. filenameWithoutExt .. "]]"
						vim.api.nvim_buf_set_text(origBuf, row - 1, col, row - 1, col, { linkFormat })
						-- Cursor should be placed right after the second ]
						vim.api.nvim_win_set_cursor(0, { row, col + #linkFormat })
					else
						-- Insert format: [[fileNameWithoutExt|input]]
						linkFormat = "[[" .. filenameWithoutExt .. "|" .. input .. "]]"
						vim.api.nvim_buf_set_text(origBuf, row - 1, col, row - 1, col, { linkFormat })
						-- Cursor should be placed right after the second ], which is the end of the linkFormat
						vim.api.nvim_win_set_cursor(0, { row, col + #linkFormat })
					end
					-- Enter insert mode after placing the cursor
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i", true, false, true), "n", true)
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
