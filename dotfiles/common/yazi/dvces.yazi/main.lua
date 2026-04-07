--- @since 25.5.31

local M = {}

local function plugin_root()
  local home = os.getenv("HOME")
  if not home or home == "" then
    error("Missing HOME; cannot locate dvces plugin files.")
  end
  return home .. "/.config/yazi/plugins/dvces.yazi/"
end

local base = plugin_root()
local fs = dofile(base .. "fs.lua")
local preview = dofile(base .. "preview.lua")

function M:entry(job)
  if preview:is_preview_delta(job) then
    return preview:entry(job)
  end

  return fs:entry(job)
end

function M:peek(job)
  return preview:peek(job)
end

function M:seek(job)
  return preview:seek(job)
end

return M
