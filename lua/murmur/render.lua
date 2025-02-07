--------------------------------------------------------------------------------
-- UI rendering module for murmur.nvim
--------------------------------------------------------------------------------

local helpers = require("murmur.helper")
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
    local border = style.border or "single"
    local zindex = style.zindex or 50
    
    -- Create buffer if not provided
    buf = buf or vim.api.nvim_create_buf(false, not opts.persist)
    
    -- Initial window setup with dummy values (will be resized immediately)
    local options = {
        relative = "editor",
        width = 10,
        height = 10,
        row = 10,
        col = 10,
        style = "minimal",
        border = border,
        title = title,
        title_pos = "center",
        zindex = zindex
    }
    
    -- Create the window
    local win = vim.api.nvim_open_win(buf, true, options)
    
    -- Create resize function that properly positions the window
    local function resize()
        local ew = vim.api.nvim_get_option_value("columns", {})
        local eh = vim.api.nvim_get_option_value("lines", {})
        
        local w, h, r, c = size_func(ew, eh)
        
        if w <= 0 or h <= 0 then
            vim.notify("Invalid window dimensions", vim.log.levels.ERROR)
            return
        end
        
        -- Update window configuration with calculated dimensions
        vim.api.nvim_win_set_config(win, {
            relative = "editor",
            width = math.floor(w),
            height = math.floor(h),
            row = math.floor(r),
            col = math.floor(c)
        })
    end
    
    -- Set up window management
    local pgid = opts.gid or helpers.create_augroup("MurmurPopup", { clear = true })
    
    -- Cleanup function
    local function close()
        -- Remove autogroup if it was created internally
        if not opts.gid then
            vim.api.nvim_del_augroup_by_id(pgid)
        end
        -- Close window if valid
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        -- Delete buffer if not persistent
        if not opts.persist and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    
    -- Set up auto-commands for window management
    helpers.autocmd("VimResized", { buf }, resize, pgid)
    helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, pgid)
    
    -- Handle buffer leave if specified
    if opts.on_leave then
        helpers.autocmd({ "BufEnter" }, nil, function(event)
            if event.buf ~= buf then
                close()
                vim.schedule(function()
                    vim.api.nvim_set_current_buf(event.buf)
                end)
            end
        end, pgid)
    end
    
    -- Set up escape handlers if specified
    if opts.escape then
        helpers.set_keymap({ buf }, "n", "<esc>", close)
        helpers.set_keymap({ buf }, { "n", "v", "i" }, "<C-c>", close)
    end
    
    -- Initial window positioning
    resize()
    
    return buf, win, close, resize
end

-- Rest of your existing functions remain the same
R.update_popup = function(buf, lines, highlight)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    if highlight then
        vim.api.nvim_buf_add_highlight(buf, -1, "MurmurStatus", 0, 0, -1)
    end
end

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

R.setup_highlights = function()
    vim.api.nvim_set_hl(0, "MurmurStatus", { link = "Normal" })
    vim.api.nvim_set_hl(0, "MurmurError", { link = "ErrorMsg" })
    vim.api.nvim_set_hl(0, "MurmurWarning", { link = "WarningMsg" })
end

return R
