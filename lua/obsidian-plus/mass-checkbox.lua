local M = {}
local obsidian = require("obsidian") -- Adjust this require statement as necessary

function M.runCommandOnSelectedLines()
	-- Get the range of the visual selection
	local range_start, range_end = unpack(vim.fn.getpos("'<"), 2, 3), unpack(vim.fn.getpos("'>"), 2, 3)

	-- Iterate over each line in the visual block selection
	for line = range_start, range_end do
		-- Retrieve the content of the line
		obsidian.util.toggle_checkbox(nil, line)
	end
end

return M
-- TODO REVISIT
