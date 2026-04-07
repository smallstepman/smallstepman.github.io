--- @since 25.5.31

local M = {}
local debug_enabled = os.getenv("DVCES_DEBUG") == "1"

local function dbg(...)
  if debug_enabled then
    ya.dbg("[dvces/preview]", ...)
  end
end

local state = ya.sync(function(st, op, key, value)
  st.scroll = st.scroll or {}
  if op == "get" then
    return st.scroll[key] or 0
  end
  if op == "clear" then
    st.scroll[key] = nil
    return 0
  end
  st.scroll[key] = math.max(0, tonumber(value) or 0)
  return st.scroll[key]
end)

local current_preview = ya.sync(function()
  local hovered = cx.active.current.hovered
  if not hovered then
    return nil
  end
  return {
    url = Url(hovered.url),
    name = hovered.name,
    skip = cx.active.preview.skip,
  }
end)

local function requested_preview_delta(job)
  if job.args.preview_delta ~= nil then
    return tonumber(job.args.preview_delta)
  end

  if job.args["preview-delta"] ~= nil then
    return tonumber(job.args["preview-delta"])
  end

  local arg = job.args[1]
  if type(arg) ~= "string" then
    return nil
  end

  local named = arg:match("^%-%-preview%-delta=(.+)$")
  if named then
    return tonumber(named)
  end

  return nil
end

function M:is_preview_delta(job)
  return requested_preview_delta(job) ~= nil
end

local function split_lines(text)
  text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then
    lines[1] = ""
  end
  return lines
end

local function read_descriptor(path)
  local output, err = Command("python3")
    :arg({
      "-c",
      [[import json, pathlib, sys; print(json.dumps(json.loads(pathlib.Path(sys.argv[1]).read_text())))]],
      path,
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if not output or not output.status.success then
    local msg = err or (output and (output.stderr ~= "" and output.stderr or output.stdout)) or "failed to read descriptor"
    return nil, tostring(msg)
  end

  local text = output.stdout:gsub("%s+$", "")
  local source = text:match('"source"%s*:%s*"([^"]+)"')
  local schema = text:match('"schema"%s*:%s*"([^"]+)"')
  local name = text:match('"name"%s*:%s*"([^"]+)"')
  local kind = text:match('"kind"%s*:%s*"([^"]+)"')
  if not source or not schema or not name then
    return nil, "invalid DuckDB preview descriptor"
  end

  return { source = source, schema = schema, name = name, kind = kind or "table" }
end

local function sql_ident(value)
  return '"' .. tostring(value):gsub('"', '""') .. '"'
end

local function sql_truncated_expr(name, width)
  local ident = sql_ident(name)
  local alias = ui.truncate(tostring(name), { max = math.max(width - 1, 1) })
  return string.format(
    "LEFT(CAST(%s AS VARCHAR), %d) AS %s",
    ident,
    math.max(width, 1),
    sql_ident(alias)
  )
end

local function parse_single_column_csv(text)
  local values = {}
  for line in (text or ""):gmatch("([^\n]+)") do
    line = line:gsub("\r$", "")
    if line ~= "" then
      if line:sub(1, 1) == '"' and line:sub(-1) == '"' then
        line = line:sub(2, -2):gsub('""', '"')
      end
      values[#values + 1] = line
    end
  end
  return values
end

local function load_columns(desc)
  local schema = tostring(desc.schema):gsub("'", "''")
  local name = tostring(desc.name):gsub("'", "''")
  local query = string.format(
    "SELECT column_name FROM duckdb_columns() WHERE schema_name = %s AND table_name = %s AND internal = false ORDER BY column_index;",
    "'" .. schema .. "'",
    "'" .. name .. "'"
  )

  local output, err = Command("duckdb")
    :arg({
      "-readonly",
      desc.source,
      "-c",
      ".mode csv",
      "-c",
      ".headers off",
      "-c",
      query,
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if not output or not output.status.success then
    local msg = err or (output and (output.stderr ~= "" and output.stderr or output.stdout)) or "failed to load columns"
    return nil, tostring(msg)
  end

  return parse_single_column_csv(output.stdout)
end

local function clamp_scroll(key, total, width)
  local span = math.max(width - 1, 1)
  local max_scroll = math.max(0, total - span)
  local current = state("get", key)
  if current > max_scroll then
    current = state("set", key, max_scroll)
  end
  return current, max_scroll
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

local function query_rows(job, desc)
  local key = tostring(job.file.url)
  local limit = math.max(job.area.h - 6, 3)
  local offset = math.max(job.skip, 0)
  local relation = sql_ident(desc.schema) .. "." .. sql_ident(desc.name)
  local columns, columns_err = load_columns(desc)
  if not columns then
    return nil, columns_err
  end
  if #columns == 0 then
    return "No columns found for this relation."
  end

  local width = math.max(math.floor((job.area.w - 2) / 12), 1)
  local scroll, max_scroll = clamp_scroll(key, #columns, width)
  local selected = {}
  for i = scroll + 1, math.min(#columns, scroll + width) do
    selected[#selected + 1] = columns[i]
  end
  if #selected == 0 then
    selected[1] = columns[#columns]
  end

  local cell_width = math.max(math.floor((job.area.w - 6 - #selected * 3) / #selected), 6)
  local rendered = {}
  for i = 1, #selected do
    rendered[i] = sql_truncated_expr(selected[i], cell_width)
  end

  local query = string.format(
    "SELECT row_number() OVER () AS row_id, %s FROM %s LIMIT %d OFFSET %d;",
    table.concat(rendered, ", "),
    relation,
    limit,
    offset
  )

  local output, err = Command("duckdb")
    :arg({
      "-readonly",
      desc.source,
      "-c",
      ".mode duckbox",
      "-c",
      ".timer off",
      "-c",
      "SET enable_progress_bar = false;",
      "-c",
      string.format(".maxwidth %d", math.max(job.area.w * 3, 80)),
      "-c",
      string.format(".maxrows %d", math.max(job.area.h, 10)),
      "-c",
      ".highlight_results on",
      "-c",
      query,
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if not output or not output.status.success then
    local msg = err or (output and (output.stderr ~= "" and output.stderr or output.stdout)) or "duckdb query failed"
    return nil, tostring(msg)
  end

  local header = string.format(
    "[%s] cols %d-%d of %d%s",
    desc.kind,
    scroll + 1,
    math.min(#columns, scroll + #selected),
    #columns,
    max_scroll > 0 and "  (H/L or horizontal wheel)" or ""
  )

  local body = output.stdout ~= "" and output.stdout or output.stderr
  return header .. "\n" .. body
end

function M:entry(job)
  local delta = requested_preview_delta(job)
  dbg("entry", { args = job.args, delta = delta })
  if not delta then
    dbg("entry -> no delta")
    return
  end

  local preview = current_preview()
  if not preview or preview.name ~= "rows.duckdbvfs" then
    dbg("entry -> not rows.duckdbvfs", { preview = preview and preview.name or nil })
    return
  end

  local key = tostring(preview.url)
  local current = state("get", key)
  dbg("entry -> scroll", { key = key, current = current, delta = delta, skip = preview.skip })
  state("set", key, current + math.floor(delta))
  ya.emit("peek", { preview.skip, force = true, only_if = Url(preview.url) })
end

function M:peek(job)
  dbg("peek", { file = job.file and job.file.name, skip = job.skip })
  if job.file.name ~= "rows.duckdbvfs" then
    dbg("peek -> clear")
    state("clear", tostring(job.file.url))
    return
  end

  local desc, err = read_descriptor(tostring(job.file.path))
  if not desc then
    dbg("peek -> descriptor error", { err = err })
    return render(job, "DuckDB preview error:\n" .. tostring(err))
  end

  local output, query_err = query_rows(job, desc)
  if not output then
    dbg("peek -> query error", { err = query_err })
    return render(job, "DuckDB preview error:\n" .. tostring(query_err))
  end

  dbg("peek -> render", { desc = desc.kind, name = desc.name })
  return render(job, output)
end

function M:seek(job)
  dbg("seek", { file = job.file and job.file.name, units = job.units })
  if type(job.units) ~= "number" then
    dbg("seek -> non-number", { skip = cx.active.preview and cx.active.preview.skip or nil })
    ya.emit("peek", { cx.active.preview.skip, force = true, only_if = job.file.url })
    return
  end

  local hovered = cx.active.current.hovered
  if not hovered or hovered.url ~= job.file.url then
    dbg("seek -> hovered mismatch", { hovered = hovered and hovered.name or nil })
    return
  end

  local page = math.max(job.area.h - 6, 3)
  local step = job.units < 0 and -page or page
  dbg("seek -> peek", { step = step, skip = cx.active.preview.skip })

  ya.emit("peek", {
    math.max(0, cx.active.preview.skip + step),
    force = true,
    only_if = job.file.url,
  })
end

return M
