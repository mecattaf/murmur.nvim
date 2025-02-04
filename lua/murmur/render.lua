--------------------------------------------------------------------------------
-- UI rendering module for murmur.nvim
--------------------------------------------------------------------------------

local logger = require("murmur.logger")

local R = {}

-- Create centered popup window
---@param buf number | nil # buffer number or nil for new buffer
---@param title string # window title
---@param size_func function # function(width, height) -> width, height, row, col
---@param opts table # options for window behavior
---@param style table | nil # visual style options
---@return number, number, function, function # buffer, window, close function, resize function
R.popup = function(buf, title, size_func, opts, style)
    opts = opts or {}
    style = style or {}
    
    -- Create or use provided buffer
    buf = buf or vim.api.nvim_create_buf(false, true)
    
    -- Set up window options
    local options = {
        relative = "editor",
        style = "minimal",
        border = style.border or "single",
        title = title,
        title_pos = "center",
        zindex = 50
    }
    
    -- Create window
    local win = vim.api.nvim_open_win(buf, true, options)
    
    -- Resize function
    local function resize()
        local width = vim.api.nvim_get_option_value("columns", {})
        local height = vim.api.nvim_get_option_value("lines", {})
        
        local w, h, row, col = size_func(width, height)
        
        -- Validate dimensions
        if w <= 0 or h <= 0 then
            logger.error("Invalid window dimensions")
            return
        end
        
        -- Update window config
        vim.api.nvim_win_set_config(win, {
            relative = "editor",
            width = math.floor(w),
            height = math.floor(h),
            row = math.floor(row),
            col = math.floor(col)
        })
    end
    
    -- Initial resize
    resize()
    
    -- Close function
    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if opts.delete_buffer and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    
    return buf, win, close, resize
end

-- Update popup content with status message
---@param buf number # buffer number
---@param lines table # lines to display
---@param highlight boolean # whether to highlight the text
R.update_popup = function(buf, lines, highlight)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    if highlight then
        vim.api.nvim_buf_add_highlight(buf, -1, "MurmurStatus", 0, 0, -1)
    end
end

-- Show error message in popup
---@param buf number # buffer number
---@param message string # error message
R.show_error = function(buf, message)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    
    local lines = {
        "",
        "    ❌ Error:",
        "    " .. message,
        ""
    }
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(buf, -1, "MurmurError", 1, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "MurmurError", 2, 0, -1)
end

-- Set up highlights
R.setup_highlights = function()
    vim.api.nvim_set_hl(0, "MurmurStatus", { link = "Normal" })
    vim.api.nvim_set_hl(0, "MurmurError", { link = "ErrorMsg" })
    vim.api.nvim_set_hl(0, "MurmurWarning", { link = "WarningMsg" })
end

return R

