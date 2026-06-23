require("recycle-bin"):setup()
require("duckdb"):setup({ mode = "standard" })

local orig_preview_touch = Preview.touch or function() end

function Preview:touch(event, step)
    local hovered = cx.active.current.hovered
    if hovered and hovered.name == "rows.duckdbvfs" then
      ya.emit("plugin", { "dvces", preview_delta = ya.clamp(-1, step, 1) })
      return
    end
    ya.emit("seek", { step })
    return orig_preview_touch(self, event, step)
end
