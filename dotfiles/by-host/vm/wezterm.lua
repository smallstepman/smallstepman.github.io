local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

config.automatically_reload_config = true

config.default_prog = { 'zsh' }
config.font = wezterm.font('JetBrains Mono')
config.font_size = 12.0
config.window_background_opacity = 0.95
config.window_close_confirmation = 'NeverPrompt'

-- Load noctalia-generated colors if available
local colors_file = wezterm.home_dir .. '/.local/share/noctalia/wezterm-colors.lua'
local ok, colors = pcall(dofile, colors_file)
if ok and type(colors) == 'table' then
  config.colors = colors
end

config.status_update_interval = 250

-- Keybinds to match macOS since this is a VM (Ctrl-based)
config.keys = {
  { key = 'c', mods = 'CTRL',       action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL',       action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = '=', mods = 'CTRL',       action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'CTRL',       action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'CTRL',       action = wezterm.action.ResetFontSize },
  { key = 'q', mods = 'CTRL',       action = wezterm.action.QuitApplication },
  { key = ',', mods = 'CTRL|SHIFT', action = wezterm.action.ReloadConfiguration },
  { key = 'k', mods = 'CTRL',       action = wezterm.action.ClearScrollback 'ScrollbackAndViewport' },
  { key = 'n', mods = 'CTRL',       action = wezterm.action.SpawnWindow },
  { key = 'w', mods = 'CTRL',       action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentTab { confirm = false } },
  { key = 't', mods = 'CTRL',       action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = '[', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = ']', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'd', mods = 'CTRL',       action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = ']', mods = 'CTRL',       action = wezterm.action.ActivatePaneDirection 'Next' },
  { key = '[', mods = 'CTRL',       action = wezterm.action.ActivatePaneDirection 'Prev' },
}

return config
