# murmur.nvim Development Guidelines

This document outlines the development standards and structure for murmur.nvim, a Neovim plugin providing offline speech-to-text capabilities through whisper.cpp integration.

## Function Definition Style

All helper functions should follow this documentation and assignment style:

```lua
---@param device_name string # recording device identifier
---@param duration number # recording duration in seconds
---@return boolean # true if recording was successful
_H.record_audio = function(device_name, duration)
    -- Implementation
end

---@param audio_path string # path to recorded audio file
---@param config table # whisper configuration options
---@return string|nil # transcribed text or nil on error
_H.process_audio = function(audio_path, config)
    -- Implementation
end
```

Avoid using the traditional function declaration style:

```lua
-- Don't use this style
function _H.record_audio(device_name, duration)
    -- Implementation
end
```

## Module Structure

murmur.nvim follows a focused module structure targeting offline speech-to-text functionality:

```lua
local uv = vim.uv or vim.loop

-- Core configuration
local config = require("murmur.config")

-- Main module structure
local M = {
    _Name = "Murmur",                           -- Plugin identifier
    _state = {},                                -- Internal state management
    cmd = {},                                   -- Command functions
    config = {},                                -- Configuration storage
    helpers = require("murmur.helper"),         -- Utility functions
    logger = require("murmur.logger"),          -- Logging system
    render = require("murmur.render"),          -- UI components
    spinner = require("murmur.spinner"),        -- Progress indicators
    whisper = require("murmur.whisper"),        -- Whisper.cpp integration
}
```

## Core Components

### Whisper Integration
The whisper.cpp integration is the heart of the plugin, handling:
- Audio recording via SoX
- Communication with whisper.cpp binary
- Transcription result processing
- Error handling and recovery

### Configuration Management
Manages essential settings including:
- Whisper.cpp binary and model paths
- Recording parameters (quality, duration, etc.)
- Interface preferences
- Language settings

### Buffer Management
Handles Neovim buffer operations:
- Creating/updating buffers with transcriptions
- Managing temporary files
- Handling multi-buffer operations

## Error Handling Standards

Use the logger module consistently for error management:

```lua
-- Example error handling pattern
if not vim.fn.executable(binary_path) then
    logger.error(string.format(
        "Whisper binary not found at %s. Please check your configuration.",
        binary_path
    ))
    return nil
end

-- Warning for non-critical issues
if quality_setting < recommended_min then
    logger.warn("Recording quality below recommended minimum")
end
```

## Audio Processing Guidelines

1. Pre-processing checks:
```lua
local function validate_audio_settings(config)
    assert(config.sample_rate > 0, "Invalid sample rate")
    assert(config.duration > 0, "Invalid duration")
    -- Additional validation
end
```

2. Resource cleanup:
```lua
local function cleanup_temp_files(paths)
    for _, path in ipairs(paths) do
        if vim.fn.filereadable(path) == 1 then
            vim.fn.delete(path)
        end
    end
end
```

3. Error recovery:
```lua
local function safe_transcribe(audio_path)
    local success, result = pcall(whisper.transcribe, audio_path)
    if not success then
        logger.error("Transcription failed: " .. result)
        return nil
    end
    return result
end
```

## Testing Guidelines

1. Unit Tests
- Test each component in isolation
- Mock whisper.cpp responses
- Verify error handling

2. Integration Tests
- Test full recording-to-transcription flow
- Verify buffer management
- Test configuration handling

## Documentation Standards

All public functions must include comprehensive documentation:

```lua
---@param opts table # Configuration options for recording
---@param callback function # Called with transcribed text
---@return boolean # true if recording started successfully
M.start_recording = function(opts, callback)
    -- Validate options
    if not opts.device then
        opts.device = M.config.default_device
    end
    
    -- Implementation continues...
end
```

## User Interface Guidelines

1. Progress Indicators
- Show clear recording status
- Indicate transcription progress
- Provide error feedback

2. Buffer Management
- Use consistent formatting
- Support multiple output modes
- Handle window management properly

## Configuration Example

```lua
{
    whisper = {
        binary = "path/to/whisper",
        model = "path/to/model.bin",
        language = "en",
    },
    recording = {
        sample_rate = 16000,
        channels = 1,
        duration = 300,
    },
    interface = {
        floating = true,
        border = "single",
    },
}
```
