# auto-colorscheme.nvim 🌓

A lightweight Neovim plugin for macOS that automatically switches your editor theme to follow the system appearance (Dark/Light).

## ✨ Features

- **Automatic detection**: Uses the native macOS `defaults` command to read the system appearance.
- **Non-blocking**: Runs checks with LuaJIT `uv` timers so editor performance stays unaffected.
- **LazyVim friendly**: Disables itself on non-macOS systems to avoid interfering with other setups.
- **Highly configurable**: Set custom dark/light schemes and polling interval.
- **Manual control**: Command provided to force a theme mode at any time.

## 📦 Dependencies (Important)

The **default configuration** assumes these themes are installed:

- Dark: `tokyonight` from [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim)
- Light: `dayfox` from [EdenEast/nightfox.nvim](https://github.com/EdenEast/nightfox.nvim)

If you do not use these themes, update the `darkScheme` and `lightScheme` values in `setup()` to match themes that are installed.

## ⚡️ Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "your-username/auto-colorscheme.nvim",
  lazy = false, -- must load at startup so detection runs immediately
  priority = 1000, -- load before other colorscheme plugins

  -- Optional: declare theme dependencies so they are installed automatically
  dependencies = {
    "folke/tokyonight.nvim",
    "EdenEast/nightfox.nvim",
  },

  config = function()
    require("auto-colorscheme").setup({
      mode = "auto",
      -- If you change these, make sure the themes are installed or declared above
      darkScheme = "tokyonight",
      lightScheme = "dayfox",
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/auto-colorscheme.nvim",
  requires = {
    "folke/tokyonight.nvim",
    "EdenEast/nightfox.nvim",
  },
  config = function()
    require("auto-colorscheme").setup({
      mode = "auto",
      darkScheme = "tokyonight",
      lightScheme = "dayfox",
    })
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'folke/tokyonight.nvim'
Plug 'EdenEast/nightfox.nvim'
Plug 'your-username/auto-colorscheme.nvim'

" In init.vim or init.lua
lua << EOF
require("auto-colorscheme").setup({
  mode = "auto",
  darkScheme = "tokyonight",
  lightScheme = "dayfox",
})
EOF
```

## 🚀 Usage

The plugin starts in `auto` mode and follows the system appearance.

### Command

Use `:AutoColorscheme` to control the mode:

- `:AutoColorscheme auto` - Resume following the system.
- `:AutoColorscheme light` - Force light mode and stop automatic checks.
- `:AutoColorscheme dark` - Force dark mode and stop automatic checks.

## ⚙️ Configuration

Default configuration:

```lua
require("auto-colorscheme").setup({
  -- Operating mode: "auto" (follow system) | "light" | "dark"
  mode = "auto",

  -- Polling interval in milliseconds
  interval = 2000,

  -- Colorscheme to use in dark mode (must be installed)
  darkScheme = "tokyonight",

  -- Colorscheme to use in light mode (must be installed)
  lightScheme = "dayfox",

  -- Show notifications when switching
  notify = true,
})
```

## ⚠️ Notes

- **macOS only**: Relies on the `defaults` command. On Linux/Windows the plugin exits early and does nothing.
- **Colorscheme existence**: Themes are loaded with `pcall`; if a theme is missing, the background may change but the colorscheme will not.

## 📄 License

MIT
