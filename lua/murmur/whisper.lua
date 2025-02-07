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
    if opts.disable then
        W.disabled = true
        return
    end

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
            sample_rate = 16000,
            -- Initialize audio processing settings from opts or use defaults
            processing = vim.tbl_deep_extend("keep", 
                opts.recording and opts.recording.processing or {},
                require("murmur.config").recording.processing
            )
        },
        store_dir = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/murmur"
    }

    -- Prepare directories and register commands
    W.config.store_dir = helpers.prepare_dir(W.config.store_dir, "murmur store")
    W.config.temp_dir = helpers.prepare_dir(W.config.store_dir .. "/temp", "murmur temp")
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

-- Process recorded audio using our enhanced audio pipeline
local function process_recording(input_file, output_file, config)
    -- First measure the RMS level to calibrate our processing
    local rms_level = helpers.get_rms_level(input_file)
    if not rms_level then
        return false, "Failed to measure audio levels"
    end
    
    -- Adjust silence threshold based on measured RMS level
    local silence_threshold = rms_level * config.recording.processing.silence.rms_threshold
    config.recording.processing.silence.rms_threshold = silence_threshold
    
    -- Process the audio through our enhanced pipeline
    local success, err = helpers.process_audio(input_file, output_file, config)
    if not success then
        return false, err
    end
    
    return true
end

-- Core recording and transcription function
local whisper = function(callback)
    -- Verify server availability
    if not check_server() then
        vim.notify("NPU server not available", vim.log.levels.ERROR)
        return
    end

    -- Initialize session state with temporary files
    local session = {
        gid = helpers.create_augroup("MurmurRecord", { clear = true }),
        timer = nil,
        continue = false,
        raw_file = helpers.temp_file("raw", ".wav"),
        processed_file = helpers.temp_file("processed", ".wav"),
        cleanup_in_progress = false
    }

    -- Recording configuration with proper audio format settings
    local rec_options = {
        sox = {
            cmd = "sox",
            opts = {
                "-c", "1",           -- Mono channel
                "-r", "16000",       -- Force 16kHz sample rate
                "--buffer", "32",    -- Buffer size
                "-b", "16",          -- 16-bit depth
                "-e", "signed-integer", -- PCM format
                "-d",                -- Input from audio device
                "rec.wav",           -- Output file (replaced at runtime)
                "trim", "0", "3600"  -- Recording duration limit
            },
            exit_code = 0
        },
        arecord = {
            cmd = "arecord",
            opts = {
                "-c", "1",
                "-f", "S16_LE",
                "-r", "16000",       -- Match required sample rate
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
                "-ar", "16000",      -- Match required sample rate
                "-t", "3600",
                "rec.wav"
            },
            exit_code = 255
        }
    }

    -- Create recording interface with proper state handling
    local buf, _, close_popup, _ = render.popup(
        nil,
        string.format("Murmur Recording [%s]", W.config.server.model),
        function(w, h)
            return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
        end,
        { gid = session.gid, on_leave = false, escape = false, persist = false }
    )

    -- Initialize status display with proper state checking
    local counter = 0
    session.timer = uv.new_timer()
    session.timer:start(
        0,
        200,
        vim.schedule_wrap(function()
            if not session.cleanup_in_progress and vim.api.nvim_buf_is_valid(buf) then
                -- Get current RMS level if available
                local level_indicator = ""
                if vim.fn.filereadable(session.raw_file) == 1 then
                    local rms = helpers.get_rms_level(session.raw_file)
                    if rms then
                        level_indicator = string.format(" (Level: %.1f dB)", rms)
                    end
                end
                
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                    "   ",
                    "   Recording using NPU-accelerated model: " .. W.config.server.model,
                    "   Speak 🎤 " .. string.rep("📝", counter % 5) .. level_indicator,
                    "   ",
                    "   Press <Enter> to finish recording and start transcription",
                    "   Cancel with <esc>/<C-c>",
                    "   ",
                    "   Recordings stored in: " .. W.config.store_dir,
                })
                counter = counter + 1
            end
        end)
    )

    -- Enhanced cleanup handler with temporary file removal
    local close = tasker.once(function()
        if session.cleanup_in_progress then return end
        session.cleanup_in_progress = true

        if session.timer then
            pcall(function()
                session.timer:stop()
                session.timer:close()
            end)
            session.timer = nil
        end

        -- Clean up temporary files
        for _, file in ipairs({session.raw_file, session.processed_file}) do
            if vim.fn.filereadable(file) == 1 then
                vim.fn.delete(file)
            end
        end

        close_popup()
        vim.api.nvim_del_augroup_by_id(session.gid)
        tasker.stop()
    end)

    -- Enhanced transcription handler with audio processing
    local function transcribe()
        -- Process the recorded audio
        vim.api.nvim_buf_set_lines(buf, 2, 3, false, {
            "   Processing audio... Please wait"
        })
        
        local success, err = process_recording(session.raw_file, session.processed_file, W.config)
        if not success then
            vim.notify("Audio processing failed: " .. err, vim.log.levels.ERROR)
            return
        end

        -- Prepare transcription request
        local endpoint = string.format(
            "http://%s:%d/transcribe/%s",
            W.config.server.host,
            W.config.server.port,
            W.config.server.model
        )

        local curl_cmd = string.format(
            'curl -X POST -H "Content-Type: audio/wav" --data-binary "@%s" %s',
            session.processed_file,
            endpoint
        )

        -- Update status
        vim.api.nvim_buf_set_lines(buf, 2, 3, false, {
            "   Transcribing... Please wait"
        })

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

    -- Set up interface controls with proper cleanup
    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", function()
        tasker.stop()
    end)

    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", function()
        tasker.stop()
    end)

    helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
        session.continue = true
        vim.defer_fn(function()
            tasker.stop()
        end, 300)
    end)

    -- Set up cleanup handlers
    helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, session.gid)

    -- Initialize recording command with proper defaults
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

    -- Configure recording command with proper error handling
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

    -- Update recording file path
    for i, v in ipairs(cmd.opts) do
        if v == "rec.wav" then
            cmd.opts[i] = session.raw_file
        end
    end

    -- Start recording process with proper cleanup
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

        if not session.continue then
            return
        end

        vim.schedule(function()
            transcribe()
        end)
    end)
end

-- Public interface remains unchanged
W.Whisper = function(callback)
    whisper(callback)
end

-- Command implementation remains unchanged
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

-- Enhanced health check implementation
W.check_health = function()
    if W.disabled then
        vim.health.warn("murmur is disabled")
        return
    end

    -- Check for sox and its capabilities
    if vim.fn.executable("sox") == 1 then
        -- Verify sox has required effects
        local sox_effects = vim.fn.system("sox --help 2>&1")
        local required_effects = {
            "compand",
            "norm",
            "highpass",
            "lowpass",
            "silence"
        }
        
        local missing_effects = {}
        for _, effect in ipairs(required_effects) do
            if not sox_effects:match(effect) then
                table.insert(missing_effects, effect)
            end
        end
        
        if #missing_effects == 0 then
            vim.health.ok("sox is installed with all required effects")
        else
            vim.health.warn("sox is missing effects: " .. table.concat(missing_effects, ", "))
        end
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
