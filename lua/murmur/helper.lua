--------------------------------------------------------------------------------
-- Helper functions for murmur.nvim
--------------------------------------------------------------------------------

local H = {}

-- All existing helper functions remain unchanged...
-- [Previous helper functions here]

-- New audio processing helpers

-- Get RMS level of audio file
---@param file string # audio file path
---@return number|nil # RMS level in dB or nil if error
H.get_rms_level = function(file)
    local handle = io.popen(string.format("sox %s -n stat 2>&1 | grep 'RMS lev dB' | awk '{print $4}'", file))
    if not handle then return nil end
    
    local result = handle:read("*a")
    handle:close()
    
    -- Convert string to number, handling potential errors
    local rms = tonumber(result)
    return rms
end

-- Construct SoX processing chain
---@param input string # input file path
---@param output string # output file path
---@param config table # processing configuration
---@return string # complete SoX command
H.build_sox_command = function(input, output, config)
    local cmd_parts = {
        "sox",
        input,
        output,
        -- Basic format enforcement
        "-c", tostring(config.recording.channels),
        "-r", tostring(config.recording.sample_rate),
        
        -- Effects chain
        "--"  -- Marker for effects
    }
    
    -- Voice enhancement
    if config.recording.processing.voice.enabled then
        table.insert(cmd_parts, "highpass")
        table.insert(cmd_parts, tostring(config.recording.processing.voice.highpass))
        table.insert(cmd_parts, "lowpass")
        table.insert(cmd_parts, tostring(config.recording.processing.voice.lowpass))
    end
    
    -- Compressor for level consistency
    if config.recording.processing.compressor.enabled then
        table.insert(cmd_parts, "compand")
        table.insert(cmd_parts, string.format("%f,%f",
            config.recording.processing.compressor.attack,
            config.recording.processing.compressor.release))
        table.insert(cmd_parts, string.format("%d,%d,%d,%d,%d,%d",
            config.recording.processing.compressor.threshold,
            config.recording.processing.compressor.threshold,
            config.recording.processing.compressor.threshold + 10,
            config.recording.processing.compressor.threshold + 10,
            0,
            config.recording.processing.compressor.threshold + 20))
        table.insert(cmd_parts, tostring(config.recording.processing.compressor.gain))
    end
    
    -- Silence processing
    if config.recording.processing.silence.enabled then
        -- Forward silence removal
        table.insert(cmd_parts, "silence")
        table.insert(cmd_parts, "1")
        table.insert(cmd_parts, tostring(config.recording.processing.silence.duration))
        table.insert(cmd_parts, string.format("%fdB", config.recording.processing.silence.rms_threshold))
        
        -- Reverse for end silence
        table.insert(cmd_parts, "reverse")
        table.insert(cmd_parts, "silence")
        table.insert(cmd_parts, "1")
        table.insert(cmd_parts, tostring(config.recording.processing.silence.duration))
        table.insert(cmd_parts, string.format("%fdB", config.recording.processing.silence.rms_threshold))
        table.insert(cmd_parts, "reverse")
    end
    
    -- Final normalization
    if config.recording.processing.voice.enabled then
        table.insert(cmd_parts, "norm")
        table.insert(cmd_parts, tostring(config.recording.processing.voice.normalize))
    end
    
    return table.concat(cmd_parts, " ")
end

-- Process recorded audio file
---@param input string # input file path
---@param output string # output file path
---@param config table # processing configuration
---@return boolean, string? # success status and error message if any
H.process_audio = function(input, output, config)
    -- Build and execute SoX command
    local cmd = H.build_sox_command(input, output, config)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return false, "Failed to execute SoX command"
    end
    
    local result = handle:read("*a")
    local success = handle:close()
    
    if not success then
        return false, "Audio processing failed: " .. result
    end
    
    return true
end

-- Validate audio processing configuration
---@param config table # processing configuration
---@return boolean, string? # validation status and error message if any
H.validate_audio_config = function(config)
    local required_fields = {
        "recording.channels",
        "recording.sample_rate",
        "recording.format"
    }
    
    for _, field in ipairs(required_fields) do
        local value = vim.fn.get(config, field:gsub("%.", "."))
        if not value then
            return false, "Missing required field: " .. field
        end
    end
    
    return true
end

-- Create temporary file path
---@param prefix string # file prefix
---@param suffix string # file suffix
---@return string # temporary file path
H.temp_file = function(prefix, suffix)
    local temp_dir = vim.fn.stdpath("data") .. "/murmur/temp"
    if vim.fn.isdirectory(temp_dir) == 0 then
        vim.fn.mkdir(temp_dir, "p")
    end
    
    return string.format("%s/%s_%d%s",
        temp_dir,
        prefix,
        os.time(),
        suffix)
end

return H
