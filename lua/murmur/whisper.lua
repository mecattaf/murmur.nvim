--------------------------------------------------------------------------------
-- Whisper module for transcribing speech using NPU-accelerated whisper.cpp server
-- This module handles audio recording and transcription using a local whisper.cpp server
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop
local render = require("murmur.render")
local helpers = require("murmur.helper")

-- Module state container
local W = {
    config = {},
    cmd = {},
    disabled = false,
    server_status = nil,
    current_model = nil
}

-- Recording configurations for different audio backends
local recording_configs = {
    sox = {
        cmd = "sox",
        opts = {
            "--buffer", "32",
            "-c", "1",           -- Mono audio
            "-r", "16000",       -- 16kHz sample rate
            "-b", "16",          -- 16-bit depth
            "-e", "signed-integer", -- PCM format
            "-d", "rec.wav",     -- Output file (replaced at runtime)
            "trim", "0", "3600"  -- Recording duration limit
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
            "rec.wav"
        },
        exit_code = 1
    },
    ffmpeg = {
        cmd = "ffmpeg",
        opts = {
            "-y",
            "-f", "avfoundation",
            "-i", ":0",
            "-ac", "1",
            "-ar", "16000",
            "-t", "3600",
            "rec.wav"
        },
        exit_code = 255
    }
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

    -- Prepare storage directory and set current model
    W.config.store_dir = helpers.prepare_dir(W.config.store_dir, "murmur store")
    W.current_model = W.config.server.model

    -- Register commands
    helpers.create_user_command("Murmur", W.cmd.Whisper)
    helpers.create_user_command("MurmurHealth", W.check_health)
end

-- Check server availability
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

-- Core recording and transcription function
local function whisper(callback)
    -- Verify server availability
    if not check_server() then
        vim.notify("NPU server not available", vim.log.levels.ERROR)
        return
    end

    -- Prepare recording session
    local session = {
        gid = helpers.create_augroup("MurmurRecord", { clear = true }),
        timer = nil,
        cleanup_in_progress = false,
        continue = false,
        rec_file = W.config.store_dir .. "/rec.wav"
    }

    -- Create recording interface
    local buf, _, close_popup, _ = render.popup(
        nil,
        string.format("Murmur Recording [%s]", W.current_model),
        function(w, h)
            return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
        end,
        { gid = session.gid, on_leave = false, escape = false, persist = false }
    )

    -- Safe cleanup function
    local function cleanup()
        if session.cleanup_in_progress then return end
        session.cleanup_in_progress = true

        -- Handle timer cleanup
        if session.timer then
            local timer = session.timer
            session.timer = nil
            pcall(function()
                timer:stop()
                timer:close()
            end)
        end

        close_popup()
        pcall(vim.api.nvim_del_augroup_by_id, session.gid)
    end

    -- Handle transcription
    local function transcribe()
        local endpoint = string.format(
            "http://%s:%d/transcribe/%s",
            W.config.server.host,
            W.config.server.port,
            W.current_model
        )

        local curl_cmd = string.format(
            'curl -X POST -H "Content-Type: multipart/form-data" '..
            '-F "audio_file=@%s" %s',
            session.rec_file,
            endpoint
        )

        local handle = io.popen(curl_cmd)
        if not handle then
            vim.notify("Failed to execute transcription request", vim.log.levels.ERROR)
            return
        end

        local result = handle:read("*a")
        handle:close()

        if result then
            local success, decoded = pcall(vim.json.decode, result)
            if success and decoded and decoded.text then
                callback(decoded.text)
            else
                vim.notify("Failed to decode server response", vim.log.levels.ERROR)
            end
        else
            vim.notify("No response from server", vim.log.levels.ERROR)
        end
    end

    -- Initialize recording status display
    local counter = 0
    session.timer = uv.new_timer()
    session.timer:start(
        0,
        200,
        vim.schedule_wrap(function()
            if not session.cleanup_in_progress and vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                    "    ",
                    "    Recording using NPU-accelerated model: " .. W.current_model,
                    "    Speak 🎤 " .. string.rep("📝", counter % 5),
                    "    ",
                    "    Press <Enter> to finish recording and start transcription",
                    "    Cancel with <esc>/<C-c>",
                    "    ",
                    "    Recordings stored in: " .. W.config.store_dir,
                })
                counter = counter + 1
            end
        end)
    )

    -- Handle recording process
    local function start_recording()
        local cmd = {}
        local rec_cmd = W.config.recording.command or "sox"

        -- Auto-detect recording command
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
        if type(rec_cmd) == "table" and rec_cmd[1] and recording_configs[rec_cmd[1]] then
            rec_cmd = vim.deepcopy(rec_cmd)
            cmd.cmd = table.remove(rec_cmd, 1)
            cmd.exit_code = recording_configs[cmd.cmd].exit_code
            cmd.opts = rec_cmd
        elseif type(rec_cmd) == "string" and recording_configs[rec_cmd] then
            cmd = vim.deepcopy(recording_configs[rec_cmd])
        else
            vim.notify(string.format("Invalid recording command: %s", rec_cmd), vim.log.levels.ERROR)
            cleanup()
            return
        end

        -- Update output file path
        for i, v in ipairs(cmd.opts) do
            if v == "rec.wav" then cmd.opts[i] = session.rec_file end
        end

        -- Start recording process
        local recording_process = vim.fn.jobstart(cmd.cmd .. " " .. table.concat(cmd.opts, " "), {
            on_exit = function(_, code)
                if code ~= cmd.exit_code then
                    vim.notify("Recording failed with code: " .. code, vim.log.levels.ERROR)
                    cleanup()
                    return
                end

                if session.continue and not session.cleanup_in_progress then
                    vim.schedule(function()
                        transcribe()
                    end)
                end
                cleanup()
            end
        })

        if recording_process <= 0 then
            vim.notify("Failed to start recording process", vim.log.levels.ERROR)
            cleanup()
        end
    end

    -- Set up interface controls
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", cleanup)
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", cleanup)
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
        session.continue = true
        vim.defer_fn(cleanup, 100)
    end)

    -- Set up cleanup handlers
    helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, cleanup, session.gid)

    -- Start recording
    start_recording()
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
        vim.health.ok(string.format("Using model: %s", W.current_model))
    else
        vim.health.error(string.format("NPU server not available at %s:%d", 
            W.config.server.host, W.config.server.port))
    end
end

return W
