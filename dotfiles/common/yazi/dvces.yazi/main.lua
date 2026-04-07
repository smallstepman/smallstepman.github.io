--- @since 25.5.31

local M = {}
local debug_enabled = os.getenv("DVCES_DEBUG") == "1"

local function dbg(...)
  if debug_enabled then
    ya.dbg("[dvces]", ...)
  end
end

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
