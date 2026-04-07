--- @since 25.5.31

local M = {}

local function plugin_dir()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return source:match("(.*/)") or "./"
end

local function helper_path()
  return plugin_dir() .. "duckdb_fs_build.py"
end

local get_context = ya.sync(function()
  local current = cx.active.current
  local hovered = cx.active.current.hovered

  return {
    cwd = Url(current.cwd),
    hovered = hovered and {
      url = Url(hovered.url),
      is_dir = hovered.cha.is_dir,
      ext = hovered.url.ext or "",
      stem = hovered.url.stem or hovered.name or "database",
    } or nil,
  }
end)

local function is_duckdb_file(item)
  return not item.is_dir and item.ext:lower() == "duckdb"
end

local function read_text(url)
  local output, err = Command("python3")
    :arg({
      "-c",
      [[import pathlib, sys; print(pathlib.Path(sys.argv[1]).read_text().strip())]],
      tostring(url),
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if not output or not output.status.success then
    local message = err or (output and (output.stderr ~= "" and output.stderr or output.stdout)) or "failed to read file"
    return nil, tostring(message)
  end

  return output.stdout:gsub("%s+$", "")
end

local function slugify(name)
  local slug = tostring(name or "database")
  slug = slug:gsub("[^%w._-]+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^%-+", "")
  slug = slug:gsub("%-+$", "")
  return slug ~= "" and slug or "database"
end

local function cache_root(item)
  local home = os.getenv("HOME")
  if not home or home == "" then
    return nil, "Missing HOME; cannot create a DuckDB cache directory."
  end

  local key = tostring(item.url)
  local hash = ya.hash(key):sub(1, 8)
  local name = string.format("%s--%s", slugify(item.stem), hash)
  return Url(home .. "/.cache/yazi/duckdb-vfs/" .. name)
end

local function build_virtual_tree(item, force)
  local root, err = cache_root(item)
  if not root then
    return nil, err
  end

  local parent = root.parent and Url(root.parent) or nil
  if not parent then
    return nil, "Could not determine the DuckDB cache directory."
  end

  local ok, create_err = fs.create("dir_all", parent)
  if not ok then
    return nil, tostring(create_err)
  end

  local args = { helper_path(), tostring(item.url), tostring(root) }
  if force then
    args[#args + 1] = "--refresh"
  end

  local output, output_err = Command("python3")
    :arg(args)
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if not output then
    return nil, tostring(output_err or "unknown error")
  end

  if not output.status.success then
    local message = output.stderr ~= "" and output.stderr or output.stdout
    message = message ~= "" and message or "unknown error"
    return nil, message
  end

  return root
end

function M:entry(job)
  local ctx = get_context()
  if not ctx then
    return
  end

  if job.args.leave then
    local marker = ctx.cwd:join("_source.txt")
    local cha = fs.cha(marker)
    if cha then
      local source, source_err = read_text(marker)
      if source and source ~= "" then
        ya.emit("reveal", { Url(source) })
        return
      elseif source_err then
        ya.notify({
          title = "DuckDB virtual FS",
          content = tostring(source_err),
          timeout = 8,
          level = "error",
        })
        return
      end
    end

    ya.emit("leave", {})
    return
  end

  local item = ctx.hovered
  if not item then
    return
  end

  if item.is_dir then
    ya.emit("enter", {})
    return
  end

  if not is_duckdb_file(item) then
    if job.args.enter_only then
      ya.emit("enter", {})
    else
      ya.emit("open", { hovered = true })
    end
    return
  end

  local root, err = build_virtual_tree(item, job.args.refresh)
  if not root then
    ya.notify({
      title = "DuckDB virtual FS",
      content = tostring(err),
      timeout = 8,
      level = "error",
    })
    return
  end

  ya.emit("cd", { root })
end

return M
