--------------------------------------------------------------------------------
-- Whisper module for transcribing speech using NPU-accelerated whisper.cpp server
-- This module handles audio recording and transcription using a local whisper.cpp server
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop
local render = require("murmur.render")
local helpers = require("murmur.helper")
local tasker = require("murmur.tasker")

-- Module state management
local W = {
    config = {},
    cmd = {},
    disabled = false,
}

---@param opts table # user config
W.setup = function(opts)
    -- Initialize default configuration
    W.config = {
        server = {
            host = opts.server and opts.server.host or "127.0.0.1",
            port = opts.server and opts.server.port or 8009,
            model = opts.server and opts.server.model or "whisper-small"
        },
        recording = {
            command = opts.recording and opts.recording.command or nil,
            format = "wav",
            channels = 1,
            sample_rate = 16000
        },
        store_dir = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/murmur"
    }

    W.config.store_dir = helpers.prepare_dir(W.config.store_dir, "murmur store")

    -- Register commands
    helpers.create_user_command("Murmur", W.cmd.Whisper)
    helpers.create_user_command("MurmurHealth", W.check_health)
end

-- Check NPU server availability
local function check_server()
    local health_url = string.format(
        "http://%s:%d/models",
        W.config.server.host,
        W.config.server.port
    )
    
    local handle = io.popen(string.format("curl -s %s", health_url))
    if not handle then return false end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        local success, decoded = pcall(vim.json.decode, result)
        if success and decoded then return true end
    end
    
    return false
end

-- Core whisper function handling recording and transcription
local whisper = function(callback)
    -- Verify server availability
    if not check_server() then
        vim.notify("NPU server not available", vim.log.levels.ERROR)
        return
    end

    -- Recording configuration
    local rec_file = W.config.store_dir .. "/rec.wav"
    local rec_options = {
        sox = {
            cmd = "sox",
            opts = {
                "-c", "1",
                "--buffer", "32",
                "-d",
                rec_file,
                "trim", "0", "3600"
            },
            exit_code = 0
        },
        arecord = {
            cmd = "arecord",
            opts = {
                "-c", "1",
                "-f", "S16_LE",
                "-r", "16000",
                "-d", "3600",
                rec_file
            },
            exit_code = 1
        },
        ffmpeg = {
            cmd = "ffmpeg",
            opts = {
                "-y",
                "-f", "avfoundation",
                "-i", ":0",
                "-t", "3600",
                rec_file
            },
            exit_code = 255
        }
    }

    local gid = helpers.create_augroup("MurmurRecord", { clear = true })

    -- Create popup interface
    local buf, _, close_popup, _ = render.popup(
        nil,
        string.format("Murmur Recording [%s]", W.config.server.model),
        function(w, h)
            return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
        end,
        { gid = gid, on_leave = false, escape = false, persist = false }
    )

    -- Initialize status display
    local counter = 0
    local timer = uv.new_timer()
    timer:start(
        0,
        200,
        vim.schedule_wrap(function()
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                    "    ",
                    "    Recording using NPU-accelerated model: " .. W.config.server.model,
                    "    Speak 🎤 " .. string.rep("📝", counter % 5),
                    "    ",
                    "    Press <Enter> to finish recording and start transcription",
                    "    Cancel with <esc>/<C-c>",
                    "    ",
                    "    Recordings stored in: " .. W.config.store_dir,
                })
            end
            counter = counter + 1
        end)
    )

    -- Set up cleanup handler using tasker
    local close = tasker.once(function()
        if timer then
            timer:stop()
            timer:close()
        end
        close_popup()
        vim.api.nvim_del_augroup_by_id(gid)
        tasker.stop()
    end)

    -- Transcription handler
    local function transcribe()
        local endpoint = string.format(
            "http://%s:%d/transcribe/%s",
            W.config.server.host,
            W.config.server.port,
            W.config.server.model
        )

        local curl_cmd = string.format(
            'curl -X POST -H "Content-Type: multipart/form-data" '..
            '-F "audio_file=@%s" %s',
            rec_file,
            endpoint
        )

        tasker.run(nil, "bash", { "-c", curl_cmd }, function(code, signal, stdout, _)
            if code ~= 0 then
                vim.notify(string.format("Transcription failed: %d, %d", code, signal), vim.log.levels.ERROR)
                return
            end

            if not stdout or stdout == "" then
                vim.notify("No response from server", vim.log.levels.ERROR)
                return
            end

            local success, decoded = pcall(vim.json.decode, stdout)
            if success and decoded and decoded.text then
                callback(decoded.text)
            else
                vim.notify("Failed to decode server response", vim.log.levels.ERROR)
            end
        end)
    end

    -- Set up interface controls
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", function()
        tasker.stop()
    end)

    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", function()
        tasker.stop()
    end)

    local continue = false
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
        continue = true
        vim.defer_fn(function()
            tasker.stop()
        end, 300)
    end)

    -- Set up cleanup handlers
    helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, gid)

    -- Initialize recording command
    local cmd = {}
    local rec_cmd = W.config.recording.command or "sox"

    -- Auto-detect recording command if not specified
    if not W.config.recording.command then
        if vim.fn.executable("ffmpeg") == 1 then
            local devices = vim.fn.system("ffmpeg -devices -v quiet | grep -i avfoundation | wc -l")
            if string.gsub(devices, "^%s*(.-)%s*$", "%1") == "1" then
                rec_cmd = "ffmpeg"
            end
        end
        if vim.fn.executable("arecord") == 1 then
            rec_cmd = "arecord"
        end
    end

    -- Configure recording command
    if type(rec_cmd) == "table" and rec_cmd[1] and rec_options[rec_cmd[1]] then
        rec_cmd = vim.deepcopy(rec_cmd)
        cmd.cmd = table.remove(rec_cmd, 1)
        cmd.exit_code = rec_options[cmd.cmd].exit_code
        cmd.opts = rec_cmd
    elseif type(rec_cmd) == "string" and rec_options[rec_cmd] then
        cmd = vim.deepcopy(rec_options[rec_cmd])
    else
        vim.notify(string.format("Invalid recording command: %s", rec_cmd), vim.log.levels.ERROR)
        close()
        return
    end

    -- Start recording process using tasker
    tasker.run(nil, cmd.cmd, cmd.opts, function(code, signal, stdout, stderr)
        close()

        if code and code ~= cmd.exit_code then
            vim.notify(
                cmd.cmd .. 
                " exited with code and signal:\ncode: " .. 
                code .. 
                ", signal: " .. 
                signal ..
                "\nstdout: " ..
                vim.inspect(stdout) ..
                "\nstderr: " ..
                vim.inspect(stderr),
                vim.log.levels.ERROR
            )
            return
        end

        if not continue then
            return
        end

        vim.schedule(function()
            transcribe()
        end)
    end)
end

-- Public interface
W.Whisper = function(callback)
    whisper(callback)
end

-- Command implementation
W.cmd.Whisper = function(params)
    local buf = vim.api.nvim_get_current_buf()
    local start_line = vim.api.nvim_win_get_cursor(0)[1]
    local end_line = start_line

    if params.range == 2 then
        start_line = params.line1
        end_line = params.line2
    end

    W.Whisper(function(text)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if text then
            vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, { text })
        end
    end)
end

-- Health check implementation
W.check_health = function()
    if W.disabled then
        vim.health.warn("murmur is disabled")
        return
    end

    if vim.fn.executable("sox") == 1 then
        vim.health.ok("sox is installed")
    else
        vim.health.error("sox is not installed - required for audio recording")
    end

    if check_server() then
        vim.health.ok(string.format("NPU server running at %s:%d", 
            W.config.server.host, W.config.server.port))
        vim.health.ok(string.format("Using model: %s", W.config.server.model))
    else
        vim.health.error(string.format("NPU server not available at %s:%d", 
            W.config.server.host, W.config.server.port))
    end
end

return W
