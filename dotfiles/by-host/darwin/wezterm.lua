local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

config.automatically_reload_config = true

config.default_prog = { 'zsh' }
config.font = wezterm.font('JetBrains Mono')
config.font_size = 12.0
config.window_background_opacity = 0.95
config.window_close_confirmation = 'NeverPrompt'

-- Use left Option key as Meta/Alt (matches macos-option-as-alt = left)
config.send_composed_key_when_left_alt_is_pressed = false

-- Non-native fullscreen (matches macos-non-native-fullscreen)
config.native_macos_fullscreen_mode = false

-- Load noctalia-generated colors if available
local colors_file = wezterm.home_dir .. '/.local/share/noctalia/wezterm-colors.lua'
local ok, colors = pcall(dofile, colors_file)
if ok and type(colors) == 'table' then
  config.colors = colors
end

config.status_update_interval = 250

-- Keybinds (Super/Cmd-based on macOS)
config.keys = {
  { key = 'c', mods = 'SUPER',       action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'SUPER',       action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'c', mods = 'SUPER|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'SUPER|SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = '=', mods = 'SUPER',       action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'SUPER',       action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'SUPER',       action = wezterm.action.ResetFontSize },
  { key = 'q', mods = 'SUPER',       action = wezterm.action.QuitApplication },
  { key = ',', mods = 'SUPER|SHIFT', action = wezterm.action.ReloadConfiguration },
  { key = 'k', mods = 'SUPER',       action = wezterm.action.ClearScrollback 'ScrollbackAndViewport' },
  { key = 'n', mods = 'SUPER',       action = wezterm.action.SpawnWindow },
  { key = 'w', mods = 'SUPER',       action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = 'w', mods = 'SUPER|SHIFT', action = wezterm.action.CloseCurrentTab { confirm = false } },
  { key = 't', mods = 'SUPER',       action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = '[', mods = 'SUPER|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = ']', mods = 'SUPER|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'd', mods = 'SUPER',       action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'SUPER|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = ']', mods = 'SUPER',       action = wezterm.action.ActivatePaneDirection 'Next' },
  { key = '[', mods = 'SUPER',       action = wezterm.action.ActivatePaneDirection 'Prev' },
}

return config
