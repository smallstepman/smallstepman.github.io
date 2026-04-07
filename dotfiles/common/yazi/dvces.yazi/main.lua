--- @since 25.5.31

local M = {}
local debug_enabled = os.getenv("DVCES_DEBUG") == "1"

local function dbg(...)
  if debug_enabled then
    ya.dbg("[dvces]", ...)
  end
end

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
  dbg("main.entry", { args = job.args })
  if preview:is_preview_delta(job) then
    dbg("main.entry -> preview")
    return preview:entry(job)
  end

  dbg("main.entry -> fs")
  return fs:entry(job)
end

function M:peek(job)
  dbg("main.peek", { file = job.file and job.file.name, skip = job.skip })
  return preview:peek(job)
end

function M:seek(job)
  dbg("main.seek", { file = job.file and job.file.name, units = job.units })
  return preview:seek(job)
end

return M
