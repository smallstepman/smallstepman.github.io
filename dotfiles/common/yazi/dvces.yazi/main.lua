--- @since 25.5.31

local M = {}

local function plugin_dir()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return source:match("(.*/)") or "./"
end

local base = plugin_dir()
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
