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
- whisper.cpp installed and configured 
- SoX for audio recording:
  - macOS: `brew install sox`
  - Ubuntu/Debian: `sudo apt-get install sox libsox-fmt-mp3`
  - Arch: `sudo pacman -S sox`
  - Fedora: `sudo dnf install sox`

[TEMPORARY: Add specific whisper.cpp installation instructions]

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "mecattaf/murmur.nvim",
    event = "VeryLazy",
    config = function()
        require("murmur").setup({
            -- Path to whisper.cpp executable
            binary_path = "path/to/whisper",
            -- Path to whisper.cpp model
            model_path = "path/to/model.bin",
            -- Optional: Override default settings
            language = "en",
            translate = false,
        })
    end
}
```

## Usage
## Basic Commands

`:MurmurToggle` - Start/stop recording
`:MurmurTranscribe [filename]` - Transcribe an existing audio file
`:MurmurReplace` - Replace selection with transcribed text
`:MurmurAppend` - Append transcribed text after selection
`:MurmurPrepend` - Prepend transcribed text before selection

[TEMPORARY: Add key mapping examples and advanced usage scenarios]

### Configuration
[TEMPORARY: Add complete configuration options based on final implementation]
```
require("murmur").setup({
    -- Default configuration shown below
    model = {
        path = vim.fn.expand("~/.local/share/murmur/models/"),
        name = "base.bin" -- Or other whisper.cpp model
    },
    recording = {
        command = nil, -- Auto-detect best recording command
        format = "wav",
        sample_rate = 16000,
        channels = 1
    },
    interface = {
        popup_border = "single",
        spinner = true,
        messages = {
            recording = "Recording... Press Enter to finish",
            processing = "Processing audio...",
            ready = "Ready for recording"
        }
    }
})
```
