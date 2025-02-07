--------------------------------------------------------------------------------
-- Task management module for murmur.nvim
-- Handles process management for audio recording and transcription
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop

local M = {}
M._handles = {}

-- Ensure function only gets called once
---@param fn function # function to wrap so it only gets called once
M.once = function(fn)
    local once = false
    return function(...)
        if once then return end
        once = true
        fn(...)
    end
end

-- Track process handles
---@param handle userdata | nil # the Lua uv handle
---@param pid number | string # the process id
---@param buf number | nil # buffer number
M.add_handle = function(handle, pid, buf)
    table.insert(M._handles, { handle = handle, pid = pid, buf = buf })
end

-- Remove process handle
---@param pid number | string # the process id to find the corresponding handle
M.remove_handle = function(pid)
    for i, h in ipairs(M._handles) do
        if h.pid == pid then
            table.remove(M._handles, i)
            return
        end
    end
end

-- Check if buffer has running process
---@param buf number | nil # buffer number
---@return boolean
M.is_busy = function(buf)
    if buf == nil then return false end
    for _, h in ipairs(M._handles) do
        if h.buf == buf then
            vim.notify("Another recording process [" .. h.pid .. "] is already running for buffer " .. buf)
            return true
        end
    end
    return false
end

-- Stop all running processes
---@param signal number | nil # signal to send to the process
M.stop = function(signal)
    if M._handles == {} then return end

    for _, h in ipairs(M._handles) do
        if h.handle ~= nil and not h.handle:is_closing() then
            uv.kill(h.pid, signal or 15)
        end
    end

    M._handles = {}
end

-- Run command with proper process management
---@param buf number | nil # buffer number
---@param cmd string # command to execute
---@param args table # arguments for command
---@param callback function | nil # exit callback function(code, signal, stdout_data, stderr_data)
---@param out_reader function | nil # stdout reader function(err, data)
---@param err_reader function | nil # stderr reader function(err, data)
M.run = function(buf, cmd, args, callback, out_reader, err_reader)
    local handle, pid
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local stdout_data = ""
    local stderr_data = ""

    if M.is_busy(buf) then return end

    local on_exit = M.once(vim.schedule_wrap(function(code, signal)
        stdout:read_stop()
        stderr:read_stop()
        stdout:close()
        stderr:close()
        if handle and not handle:is_closing() then
            handle:close()
        end
        if callback then
            callback(code, signal, stdout_data, stderr_data)
        end
        M.remove_handle(pid)
    end))

    handle, pid = uv.spawn(cmd, {
        args = args,
        stdio = { nil, stdout, stderr },
        hide = true,
        detach = true,
    }, on_exit)

    M.add_handle(handle, pid, buf)

    uv.read_start(stdout, function(err, data)
        if err then
            vim.notify("Error reading stdout: " .. vim.inspect(err), vim.log.levels.ERROR)
        end
        if data then
            stdout_data = stdout_data .. data
        end
        if out_reader then
            out_reader(err, data)
        end
    end)

    uv.read_start(stderr, function(err, data)
        if err then
            vim.notify("Error reading stderr: " .. vim.inspect(err), vim.log.levels.ERROR)
        end
        if data then
            stderr_data = stderr_data .. data
        end
        if err_reader then
            err_reader(err, data)
        end
    end)
end

return M
