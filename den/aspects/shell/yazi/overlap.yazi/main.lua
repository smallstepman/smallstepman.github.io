local M = {}
local fallback_urls = {}

local function plugin_root()
  local home = os.getenv("HOME")
  if not home or home == "" then
    error("Missing HOME; cannot locate OHLCV preview helper.")
  end
  return home .. "/.config/yazi/plugins/ohlcv.yazi/"
end

local function helper_path()
  return plugin_root() .. "preview.py"
end

local function split_lines(text)
  text = (text or ""):gsub("\r\n", "\n")

  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  if #lines == 0 then
    lines[1] = ""
  end
  return lines
end

local function render(job, text)
  local lines = split_lines(text)
  local limit = job.area.h
  local total = #lines

  if job.skip > 0 and total < job.skip + limit then
    ya.emit("peek", {
      math.max(0, total - limit),
      only_if = job.file.url,
      upper_bound = true,
    })
    return
  end

  local from = math.min(job.skip + 1, total)
  local to = math.min(total, job.skip + limit)
  local visible = {}
  for i = from, to do
    visible[#visible + 1] = lines[i]
  end

  ya.preview_widget(
    job,
    ui.Text.parse(table.concat(visible, "\n")):area(job.area):wrap(ui.Wrap.NO)
  )
end

local function ohlcv_output(job)
  return Command("python3")
    :arg({
      helper_path(),
      tostring(job.file.url.path),
      tostring(job.area.h),
      tostring(job.area.w),
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
end

local function url_key(url)
  return tostring(url)
end

local function output_succeeded(output)
  return output and output.status and output.status.success
end

function M:peek(job)
  local output = ohlcv_output(job)
  local key = url_key(job.file.url)

  if not output_succeeded(output) then
    fallback_urls[key] = true
    return require("duckdb"):peek(job)
  end

  fallback_urls[key] = nil
  local text = output.stdout ~= "" and output.stdout or output.stderr
  render(job, text)
end

function M:seek(job)
  local hovered = cx.active.current.hovered
  if not hovered or hovered.url ~= job.file.url then
    return
  end

  if fallback_urls[url_key(job.file.url)] then
    return require("duckdb"):seek(job)
  end

  local step = math.floor(job.units * job.area.h / 10)
  step = step == 0 and ya.clamp(-1, job.units, 1) or step

  ya.emit("peek", {
    math.max(0, cx.active.preview.skip + step),
    only_if = job.file.url,
  })
end

return M
