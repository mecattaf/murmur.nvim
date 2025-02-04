--------------------------------------------------------------------------------
-- Main entry point for murmur.nvim
--------------------------------------------------------------------------------

local config = require("murmur.config")
local whisper = require("murmur.whisper")
local logger = require("murmur.logger")
local render = require("murmur.render")

local M = {}

-- Setup function
---@param opts table | nil # user configuration
M.setup = function(opts)
    -- Merge user config with defaults
    opts = vim.tbl_deep_extend("force", config, opts or {})
    
    -- Initialize components
    logger.setup(opts)
    render.setup_highlights()
    whisper.setup(opts)
    
    -- Log setup completion
    logger.info("murmur.nvim initialized")
end

-- Export the module
return M
