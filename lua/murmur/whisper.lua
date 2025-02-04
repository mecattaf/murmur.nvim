--------------------------------------------------------------------------------
-- Whisper module for transcribing speech using NPU-accelerated whisper.cpp server
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop

local logger = require("murmur.logger")
local render = require("murmur.render")
local helpers = require("murmur.helper")

local W = {
    config = {},
    cmd = {},
    disabled = false,
    server_status = nil,
    current_model = nil
}

---@param opts table # user config
W.setup = function(opts)
    logger.debug("murmur setup started\n" .. vim.inspect(opts))

    -- Default configuration focusing on NPU server
    W.config = {
        server = {
            host = opts.server and opts.server.host or "127.0.0.1",
            port = opts.server and opts.server.port or 8009,
            model = opts.server and opts.server.model or "whisper-small"
        },
        recording = {
            command = opts.recording and opts.recording.command or nil, -- Will auto-detect
            format = "wav",
            channels = 1,
            sample_rate = 16000
        },
        store_dir = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/murmur"
    }

    W.config.store_dir = helpers.prepare_dir(W.config.store_dir, "murmur store")
    W.current_model = W.config.server.model

    -- Create user commands
    helpers.create_user_command("Murmur", W.cmd.Whisper)
    helpers.create_user_command("MurmurHealth", W.check_health)
    
    logger.debug("murmur setup finished")
end

-- Check NPU server status and available models
local function check_server()
    local health_url = string.format(
        "http://%s:%d/models",
        W.config.server.host,
        W.config.server.port
    )
    
    local handle = io.popen(string.format("curl -s %s", health_url))
    if not handle then
        return false
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        local success, decoded = pcall(vim.json.decode, result)
        if success and decoded then
            return true
        end
    end
    
    return false
end

-- Core whisper function handling recording and transcription
local function whisper(callback)
    -- Verify server is available
    if not check_server() then
        logger.error("NPU server not available")
        return
    end

    -- Recording setup optimized for NPU server
    local rec_file = W.config.store_dir .. "/rec.wav"
    local rec_options = {
        sox = {
            cmd = "sox",
            opts = {
                "--buffer", "32",
                "-c", "1",           -- Mono audio
                "-r", "16000",       -- 16kHz sample rate
                "-b", "16",          -- 16-bit depth
                "-e", "signed-integer", -- PCM format
                "-d", "rec.wav",
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

    local gid = helpers.create_augroup("MurmurRecord", { clear = true })

    -- Create recording popup with model indication
    local buf, _, close_popup, _ = render.popup(
        nil,
        string.format("Murmur Recording [%s]", W.current_model),
        function(w, h)
            return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
        end,
        { gid = gid, on_leave = false, escape = false, persist = false }
    )

    -- Transcription function using NPU server
    local function transcribe(audio_file)
        local endpoint = string.format(
            "http://%s:%d/transcribe/%s",
            W.config.server.host,
            W.config.server.port,
            W.current_model
        )

        local curl_cmd = string.format(
            'curl -X POST -H "Content-Type: multipart/form-data" '..
            '-F "audio_file=@%s" %s',
            audio_file,
            endpoint
        )

        local handle = io.popen(curl_cmd)
        if not handle then
            logger.error("Failed to execute transcription request")
            return
        end

        local result = handle:read("*a")
        handle:close()
        
        if result then
            local success, decoded = pcall(vim.json.decode, result)
            if success and decoded and decoded.text then
                callback(decoded.text)
            else
                logger.error("Failed to decode NPU server response: " .. result)
            end
        else
            logger.error("No response from NPU server")
        end
    end

    -- Animation frames for recording status
    local counter = 0
    local timer = uv.new_timer()
    timer:start(
        0,
        200,
        vim.schedule_wrap(function()
            if vim.api.nvim_buf_is_valid(buf) then
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
            end
            counter = counter + 1
        end)
    )

    local close = function()
        if timer then
            timer:stop()
            timer:close()
        end
        close_popup()
        vim.api.nvim_del_augroup_by_id(gid)
    end

    -- Handle recording controls
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", close)
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", close)

    local continue = false
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
        continue = true
        vim.defer_fn(close, 300)
    end)

    -- Cleanup on buffer exit
    helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, gid)

    -- Handle recording process
    local function start_recording()
        local cmd = {}
        local rec_cmd = W.config.recording.command

        if not rec_cmd then
            rec_cmd = "sox"
            if vim.fn.executable("ffmpeg") == 1 then
                local devices = vim.fn.system("ffmpeg -devices -v quiet | grep -i avfoundation | wc -l")
                devices = string.gsub(devices, "^%s*(.-)%s*$", "%1")
                if devices == "1" then
                    rec_cmd = "ffmpeg"
                end
            end
            if vim.fn.executable("arecord") == 1 then
                rec_cmd = "arecord"
            end
        end

        if type(rec_cmd) == "table" and rec_cmd[1] and rec_options[rec_cmd[1]] then
            rec_cmd = vim.deepcopy(rec_cmd)
            cmd.cmd = table.remove(rec_cmd, 1)
            cmd.exit_code = rec_options[cmd.cmd].exit_code
            cmd.opts = rec_cmd
        elseif type(rec_cmd) == "string" and rec_options[rec_cmd] then
            cmd = rec_options[rec_cmd]
        else
            logger.error(string.format("Invalid recording command: %s", rec_cmd))
            close()
            return
        end

        -- Update recording file path
        for i, v in ipairs(cmd.opts) do
            if v == "rec.wav" then
                cmd.opts[i] = rec_file
            end
        end

        -- Execute recording command
        local recording_process = vim.fn.jobstart(cmd.cmd .. " " .. table.concat(cmd.opts, " "), {
            on_exit = function(_, code)
                if code ~= cmd.exit_code then
                    logger.error("Recording failed with code: " .. code)
                    close()
                    return
                end

                if continue then
                    vim.schedule(function()
                        transcribe(rec_file)
                    end)
                end
            end
        })

        if recording_process <= 0 then
            logger.error("Failed to start recording process")
            close()
        end
    end

    -- Start recording process
    start_recording()
end

-- Public Whisper function
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
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end

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

    -- Check recording dependencies
    if vim.fn.executable("sox") == 1 then
        vim.health.ok("sox is installed")
    else
        vim.health.error("sox is not installed - required for audio recording")
    end

    -- Check NPU server
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
