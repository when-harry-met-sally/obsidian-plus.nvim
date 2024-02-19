local obsLink = require("obs.link")

local M = {}
M.setup = function(opts) end

M.test = function()
	obsLink.selectDirectoryAndCreateNote()
end

return M
