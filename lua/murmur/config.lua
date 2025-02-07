--------------------------------------------------------------------------------
-- Configuration module for murmur.nvim
--------------------------------------------------------------------------------

local config = {
    -- NPU server configuration
    server = {
        host = "127.0.0.1",
        port = 8009,
        model = "whisper-small",     -- Default model
        timeout = 30,                -- Request timeout in seconds
    },

    -- Recording configuration
    recording = {
        command = nil,               -- Auto-detect (sox, arecord, or ffmpeg)
        format = "wav",              -- Required format for NPU server
        sample_rate = 16000,         -- Must match server requirements
        channels = 1,                -- Mono audio as required
        max_duration = 3600,         -- Maximum recording duration in seconds
        
        -- Advanced audio processing settings
        processing = {
            -- Automatic Gain Control
            agc = {
                enabled = true,
                attack_time = 0.05,    -- Attack time in seconds
                release_time = 0.2,    -- Release time in seconds
                target_level = -20,    -- Target level in dB
                max_gain = 20,         -- Maximum gain in dB
            },
            
            -- Voice enhancement
            voice = {
                enabled = true,
                highpass = 100,        -- High-pass filter frequency
                lowpass = 8000,        -- Low-pass filter frequency
                normalize = -3,        -- Normalization level in dB
            },
            
            -- Silence detection
            silence = {
                enabled = true,
                rms_threshold = 1.75,  -- RMS threshold multiplier
                duration = 0.5,        -- Minimum silence duration
                padding = 0.1,         -- Silence padding in seconds
            },
            
            -- Compressor settings for consistent levels
            compressor = {
                enabled = true,
                threshold = -20,       -- Threshold in dB
                ratio = 3,            -- Compression ratio
                attack = 0.05,        -- Attack time in seconds
                release = 0.2,        -- Release time in seconds
                gain = 6,             -- Makeup gain in dB
            }
        }
    },

    -- UI configuration
    ui = {
        border = "single",           -- Popup border style
        spinner = true,              -- Show processing spinner
        messages = {
            recording = "🎤 Recording... Press Enter to finish",
            processing = "⚡ Processing with NPU acceleration...",
            ready = "Ready for recording",
            error = "Error: %s"      -- Error message template
        }
    },

    -- Storage configuration
    storage = {
        dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/murmur/recordings",
        cleanup = true,              -- Automatically cleanup old recordings
        max_files = 10,             -- Maximum number of recordings to keep
        temp_dir = nil              -- Set automatically based on system temp dir
    }
}

return config
