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
        max_duration = 3600          -- Maximum recording duration in seconds
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
        max_files = 10              -- Maximum number of recordings to keep
    }
}

return config

