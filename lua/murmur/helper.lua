--------------------------------------------------------------------------------
-- Helper functions for murmur.nvim
--------------------------------------------------------------------------------

local H = {}

-- Directory preparation with proper permissions
---@param dir string # directory to prepare
---@param name string | nil # name of the directory
---@return string # returns resolved directory path
H.prepare_dir = function(dir, name)
    dir = dir:gsub("/$", "")
    name = name and name .. " " or ""
    
    if vim.fn.isdirectory(dir) == 0 then
        vim.notify("Creating " .. name .. "directory: " .. dir, vim.log.levels.INFO)
        vim.fn.mkdir(dir, "p")
    end

    dir = vim.fn.resolve(dir)
    return dir
end

-- Clean up old recordings
---@param dir string # directory containing recordings
---@param max_files number # maximum number of files to keep
H.cleanup_recordings = function(dir, max_files)
    local files = vim.fn.glob(dir .. "/*.wav", false, true)
    if #files > max_files then
        table.sort(files, function(a, b)
            return vim.fn.getftime(a) < vim.fn.getftime(b)
        end)
        for i = 1, #files - max_files do
            vim.fn.delete(files[i])
        end
    end
end

-- Create Neovim user commands with proper handling
---@param cmd_name string # name of the command
---@param cmd_func function # function to be executed
---@param desc string | nil # optional description
H.create_user_command = function(cmd_name, cmd_func, desc)
    vim.api.nvim_create_user_command(cmd_name, cmd_func, {
        nargs = "*",
        range = true,
        desc = desc or "Murmur command",
    })
end

-- Set keymaps with proper options
---@param buffers table # table of buffer numbers
---@param modes table | string # mode(s) to set keymap for
---@param key string # key sequence
---@param callback function | string # callback function or command
H.set_keymap = function(buffers, modes, key, callback)
    if type(buffers) ~= "table" then
        buffers = { buffers }
    end
    if type(modes) ~= "table" then
        modes = { modes }
    end
    
    for _, buf in ipairs(buffers) do
        vim.keymap.set(modes, key, callback, {
            noremap = true,
            silent = true,
            buffer = buf
        })
    end
end

-- Create autocommands with proper grouping
---@param events string | table # autocommand events
---@param buffers table # buffer numbers
---@param callback function # callback function
---@param gid number # augroup ID
H.autocmd = function(events, buffers, callback, gid)
    if type(events) ~= "table" then
        events = { events }
    end
    
    for _, buf in ipairs(buffers) do
        vim.api.nvim_create_autocmd(events, {
            group = gid,
            buffer = buf,
            callback = vim.schedule_wrap(callback)
        })
    end
end

-- Create unique augroup
---@param name string # group name
---@param opts table | nil # options
---@return number # augroup ID
H.create_augroup = function(name, opts)
    opts = opts or { clear = true }
    return vim.api.nvim_create_augroup(
        name .. "_" .. tostring(math.random(1000000)), 
        opts
    )
end

-- Check if command is available
---@param cmd string # command to check
---@return boolean # true if command exists
H.has_command = function(cmd)
    return vim.fn.executable(cmd) == 1
end

-- Validate server response
---@param response string # server response
---@return boolean, table|nil # success status and decoded response
H.validate_response = function(response)
    if not response or response == "" then
        return false, nil
    end
    
    local success, decoded = pcall(vim.json.decode, response)
    if not success or not decoded then
        return false, nil
    end
    
    return true, decoded
end

return H
