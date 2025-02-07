--------------------------------------------------------------------------------
-- Main entry point for murmur.nvim
--------------------------------------------------------------------------------

local config = require("murmur.config")
local whisper = require("murmur.whisper")
local render = require("murmur.render")

local M = {}

-- Setup function
---@param opts table | nil # user configuration
M.setup = function(opts)
    -- Merge user config with defaults
    opts = vim.tbl_deep_extend("force", config, opts or {})
    
    -- Initialize components
    render.setup_highlights()
    whisper.setup(opts)
    
    -- Notify setup completion
    -- vim.notify("murmur.nvim initialized", vim.log.levels.INFO)
end

return M
