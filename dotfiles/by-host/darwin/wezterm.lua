local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()
local colors_file = wezterm.home_dir .. '/.local/share/noctalia/wezterm-colors.lua'
local scheme_file = wezterm.home_dir .. '/.config/wezterm/colors/Noctalia.toml'
local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider

local function load_scheme_colors(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end

  local colors = {}
  local in_colors = false
  local array_key = nil
  local array_values = nil

  for line in file:lines() do
    if not in_colors then
      if line:match '^%s*%[colors%]%s*$' then
        in_colors = true
      end
    elseif array_key then
      for value in line:gmatch('"([^"]+)"') do
        table.insert(array_values, value)
      end

      if line:match '%]' then
        colors[array_key] = array_values
        array_key = nil
        array_values = nil
      end
    elseif line:match '^%s*%[' then
      break
    else
      local key, value = line:match('^%s*([%w_]+)%s*=%s*"([^"]+)"')
      if key then
        colors[key] = value
      else
        local next_array_key, array_start = line:match('^%s*([%w_]+)%s*=%s*%[(.*)$')
        if next_array_key then
          array_key = next_array_key
          array_values = {}

          for value in array_start:gmatch('"([^"]+)"') do
            table.insert(array_values, value)
          end

          if array_start:match '%]' then
            colors[array_key] = array_values
            array_key = nil
            array_values = nil
          end
        end
      end
    end
  end

  file:close()

  if next(colors) ~= nil then
    return colors
  end

  return nil
end

local function shift_hex_tones(color, tones)
  if not color then
    return nil
  end

  local r, g, b = color:match '^#?(%x%x)(%x%x)(%x%x)$'
  if not r then
    return color
  end

  local delta = tones * 0x11

  local function clamp(value)
    return math.max(0, math.min(255, value))
  end

  return string.format(
    '#%02x%02x%02x',
    clamp(tonumber(r, 16) + delta),
    clamp(tonumber(g, 16) + delta),
    clamp(tonumber(b, 16) + delta)
  )
end

local function tab_title(tab_info)
  local title = tab_info.tab_title
  if not title or #title == 0 then
    title = tab_info.active_pane.title
  end

  return title
end

wezterm.on('format-tab-title', function(tab, _, _, window_config, hover, max_width)
  local window_colors = (window_config and window_config.colors) or config.colors or {}
  local palette = window_colors.tab_bar or (config.colors and config.colors.tab_bar) or {}
  local base_colors = window_colors
  local edge_background = palette.background or base_colors.background or '#000000'

  local tab_colors
  if tab.is_active then
    tab_colors = palette.active_tab or {}
  elseif hover then
    tab_colors = palette.inactive_tab_hover or palette.inactive_tab or {}
  else
    tab_colors = palette.inactive_tab or {}
  end

  local background = tab_colors.bg_color or edge_background
  local foreground = tab_colors.fg_color or base_colors.foreground or '#c0c0c0'
  local edge_foreground = background
  local inner_max_width = math.max(max_width - 4, 0)
  local title = wezterm.truncate_right(tab_title(tab), inner_max_width)

  if #title > 0 then
    title = ' ' .. title .. ' '
  end

  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_RIGHT_ARROW },
  }
end)

config.automatically_reload_config = true
wezterm.add_to_config_reload_watch_list(colors_file)
wezterm.add_to_config_reload_watch_list(scheme_file)

config.default_prog = { 'zsh' }
config.font = wezterm.font('JetBrains Mono')
config.font_size = 12.0
config.window_background_opacity = 0.95
config.window_close_confirmation = 'NeverPrompt'
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false
config.window_frame = {
  active_titlebar_bg = 'none',
  inactive_titlebar_bg = 'none',
}

-- Use left Option key as Meta/Alt (matches macos-option-as-alt = left)
config.send_composed_key_when_left_alt_is_pressed = false

-- Non-native fullscreen (matches macos-non-native-fullscreen)
config.native_macos_fullscreen_mode = false

-- Load noctalia-generated colors if available
local ok, colors = pcall(dofile, colors_file)
if ok and type(colors) == 'table' then
  config.colors = colors
end

local scheme_colors = load_scheme_colors(scheme_file)
if scheme_colors then
  config.colors = config.colors or {}

  local active_bg = scheme_colors.background or config.colors.background
  local inactive_bg = shift_hex_tones(active_bg, -3) or scheme_colors.selection_bg or active_bg
  local active_fg = scheme_colors.foreground or config.colors.foreground
  local inactive_fg = scheme_colors.selection_fg or active_fg

  config.colors.tab_bar = {
    background = inactive_bg,
    active_tab = {
      bg_color = active_bg,
      fg_color = active_fg,
    },
    inactive_tab = {
      bg_color = inactive_bg,
      fg_color = inactive_fg,
    },
    inactive_tab_hover = {
      bg_color = inactive_bg,
      fg_color = inactive_fg,
    },
    new_tab = {
      bg_color = inactive_bg,
      fg_color = inactive_fg,
    },
    new_tab_hover = {
      bg_color = active_bg,
      fg_color = active_fg,
    },
  }
end

config.window_decorations = "NONE"
config.status_update_interval = 250
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'NONE',
    action = wezterm.action.ScrollByLine(-2),
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'NONE',
    action = wezterm.action.ScrollByLine(2),
  },
}

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
