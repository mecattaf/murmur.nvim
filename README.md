<div align="center">

# 🎤 murmur.nvim

Seamless offline speech-to-text in Neovim powered by whisper.cpp

[Features](#features) • [Prerequisites](#prerequisites) • [Installation](#installation) • [Usage](#usage) • [Configuration](#configuration)

</div>

## Features

murmur.nvim transforms Neovim into your personal transcription tool by integrating whisper.cpp for offline speech-to-text capabilities. This focused fork of gp.nvim removes all third-party API dependencies to create a lightweight, privacy-respecting voice input solution.

- 🚀 **Fully Offline Operation**: Uses whisper.cpp for local speech recognition
- 🎯 **Focus on Speed**: Optimized for quick voice-to-text operations
- 🔒 **Privacy First**: All processing happens on your machine
- ⚡ **Low Latency**: Ideal for real-time transcription needs
- 🛠 **Simple Configuration**: Minimal setup required

## Prerequisites

- Neovim >= 0.9.0
- whisper.cpp server running locally
- One of the following audio recording tools:
  - SoX (recommended):
    - macOS: `brew install sox`
    - Ubuntu/Debian: `sudo apt-get install sox libsox-fmt-mp3`
    - Arch: `sudo pacman -S sox`
    - Fedora: `sudo dnf install sox`
  - arecord (Linux)
  - ffmpeg (macOS)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "mecattaf/murmur.nvim",
    event = "VeryLazy",
    opts = {
        -- Optional: Override default configuration
        server = {
            host = "127.0.0.1",  -- whisper.cpp server host
            port = 8009,         -- whisper.cpp server port
            model = "whisper-small"  -- Model to use
        },
        recording = {
            command = nil,  -- Auto-detect (sox, arecord, or ffmpeg)
        },
        ui = {
            border = "single",  -- Popup border style
            spinner = true      -- Show processing spinner
        }
    }
}
```

## Usage

### Basic Commands

- `:Murmur` - Start recording. Press Enter to finish recording and begin transcription. The transcribed text will be inserted at the cursor position or replace the selected text.
- `:MurmurHealth` - Check the health status of the plugin, including:
  - Recording tool availability (sox/arecord/ffmpeg)
  - NPU server connection
  - Model availability and configuration

### Key Mappings

You can create custom key mappings for the Murmur command. Here's an example:

```lua
vim.keymap.set('n', '<leader>r', ':Murmur<CR>', { noremap = true, silent = true })
```

### Visual Mode Support

The plugin supports both normal mode and visual mode:
- In normal mode, transcribed text is inserted at the cursor position
- In visual mode, transcribed text replaces the selected text

## Configuration

Here's the complete configuration with default values:

```lua
require("murmur").setup({
    -- NPU server configuration
    server = {
        host = "127.0.0.1",
        port = 8009,
        model = "whisper-small",
        timeout = 30  -- Request timeout in seconds
    },
    
    -- Recording configuration
    recording = {
        command = nil,  -- Auto-detect (sox, arecord, or ffmpeg)
        format = "wav",
        sample_rate = 16000,
        channels = 1,
        max_duration = 3600  -- Maximum recording duration in seconds
    },
    
    -- UI configuration
    ui = {
        border = "single",  -- Popup border style
        spinner = true,     -- Show processing spinner
        messages = {
            recording = "🎤 Recording... Press Enter to finish",
            processing = "⚡ Processing with NPU acceleration...",
            ready = "Ready for recording",
            error = "Error: %s"  -- Error message template
        }
    },
    
    -- Storage configuration
    storage = {
        dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/murmur/recordings",
        cleanup = true,     -- Automatically cleanup old recordings
        max_files = 10     -- Maximum number of recordings to keep
    }
})
```

### Recording Command Selection

The plugin automatically selects the best available recording command:
1. On macOS with AVFoundation support: `ffmpeg`
2. On Linux with ALSA: `arecord`
3. Fallback: `sox`

You can override this by setting `recording.command` in your configuration.
