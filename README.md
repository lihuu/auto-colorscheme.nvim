# auto-colorscheme.nvim 🌓

一个轻量级 Neovim 主题自动切换插件。它能根据系统的外观设置（深色/浅色模式）自动切换 Neovim 的 `background` 和 `colorscheme`。

## ✨ 特性

- **自动检测**: 自动检测系统主题。
- **非阻塞**: 使用 LuaJIT `uv` 异步定时器，完全不影响编辑器性能。
- **跨平台支持**: 支持 macOS、Windows 和 GNOME 桌面环境。
- **高度可配置**: 支持自定义深色/浅色主题、检测频率等。
- **手动控制**: 提供命令随时切换模式。

## 📦 依赖说明 (重要)

本插件的**默认配置**假设你已经安装了以下主题插件：

- 深色: `tokyonight` (来自 [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim))
- 浅色: `dayfox` (来自 [EdenEast/nightfox.nvim](https://github.com/EdenEast/nightfox.nvim))

**如果你没有安装上述主题，或者想使用其他主题，请务必在 `setup()` 配置中修改 `darkScheme` 和 `lightScheme` 字段。**

## ⚡️ 安装

### [lazy.nvim](https://github.com/folke/lazy.nvim) (推荐)

如果你使用 LazyVim 或 lazy.nvim，建议使用 `dependencies` 字段来自动安装所需的主题：

```
{
  "your-username/auto-colorscheme.nvim",
  lazy = false, -- 重要：必须设为 false 以便启动时立即检测
  priority = 1000, -- 确保在其他配色插件之前加载

  -- 可选：添加依赖以确保主题插件已被安装
  dependencies = {
    "folke/tokyonight.nvim",
    "EdenEast/nightfox.nvim",
  },

  config = function()
    require("auto-colorscheme").setup({
      mode = "auto",
      -- ⚠️ 如果修改了下面的主题，请确保它们已安装或在 dependencies 中声明
      darkScheme = "tokyonight",
      lightScheme = "dayfox",
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```
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
  end
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```
Plug 'folke/tokyonight.nvim'
Plug 'EdenEast/nightfox.nvim'
Plug 'your-username/auto-colorscheme.nvim'

" 在 init.vim 或 init.lua 中添加配置
lua << EOF
require("auto-colorscheme").setup({
  mode = "auto",
  darkScheme = "tokyonight",
  lightScheme = "dayfox",
})
EOF
```

## 🚀 使用方法

插件启动后默认处于 `auto` 模式，会自动跟随系统。

### 命令

你可以使用 `:AutoColorscheme` 命令手动控制：

- `:AutoColorscheme auto` - 恢复自动跟随系统模式。
- `:AutoColorscheme light` - 强制切换到浅色模式（停止自动检测）。
- `:AutoColorscheme dark` - 强制切换到深色模式（停止自动检测）。

## ⚙️ 配置选项

默认配置如下：

```
require("auto-colorscheme").setup({
    -- 运行模式: "auto" (跟随系统) | "light" | "dark"
    mode = "auto",

    -- 检测频率（毫秒）
    interval = 2000,

    -- 深色模式下的配色方案
    -- ⚠️ 必须是已安装的主题名称
    darkScheme = "tokyonight",

    -- 浅色模式下的配色方案
    -- ⚠️ 必须是已安装的主题名称
    lightScheme = "dayfox",

    -- 切换时是否显示通知
    notify = true,
})
```

## ⚠️ 注意事项

- **主题存在性检查**: 插件在切换主题时会使用 `pcall` 尝试加载。如果你配置的主题不存在，Neovim 不会崩溃，但主题切换会失败（可能只改变 background 而不改变 colorscheme）。

## 📄 License

MIT
