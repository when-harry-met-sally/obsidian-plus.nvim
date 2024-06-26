local obsLink = require("obsidian-plus.link")
local obsMassCheckbox = require("obsidian-plus.mass-checkbox")

local M = {}

-- Default configurations
local default_configs = {
	template_mappings = {
		-- Default mappings
	},
}

M.user_configs = vim.tbl_deep_extend("force", {}, default_configs)

-- Optional setup function for user overrides
function M.setup(user_configs)
	M.user_configs = vim.tbl_deep_extend("force", M.user_configs, user_configs or {})
	obsLink.setUserConfigs(M.user_configs) -- Pass configs to obsLink module
end

function M.test()
	obsLink.selectDirectoryAndCreateNote()
end

function M.test2()
	obsMassCheckbox.runCommandOnSelectedLines()
end

return M
