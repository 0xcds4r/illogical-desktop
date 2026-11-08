-- Example Lua desktop widget.
--
-- Put .lua files into ~/.config/illogical-impulse/desktop-widgets/ and add them
-- from Settings -> Widgets -> Custom widgets. Right-click the widget for
-- "Reload script" after editing it.
--
-- The script returns a table (or assigns the global `widget`):
--   width, height, tick      preferred size and animation interval (ms, 0 = off)
--   render(w, h)             returns a list of drawing operations
--   on_tick(ms)              animation tick
--   on_press / on_move / on_release / on_click / on_double_click / on_wheel
--   state                    persistent table, saved between restarts
--
-- Drawing operations: rect, circle, line, text, image, arc.

local W = {
    width = 300,
    height = 180,
    tick = 50,
}

local angle = 0

local function accent()
    local pulse = 0.5 + 0.5 * math.sin(angle)
    return string.format("#%02x%02x%02x",
        math.floor(90 + 80 * pulse),
        math.floor(140 + 60 * pulse),
        255)
end

function W.render(w, h)
    local clicks = (W.state and W.state.clicks) or 0
    local radius = 24 + 3 * math.sin(angle)
    return {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "#12141a", border = 1, borderColor = "#2b3140" },
        { type = "circle", x = w / 2, y = h / 2 - 16, r = radius, color = accent() },
        { type = "text", x = w / 2, y = h - 52, text = "Lua widget",
          size = 18, color = "#ffffff", align = "center" },
        { type = "text", x = w / 2, y = h - 28, text = "clicks: " .. clicks,
          size = 13, color = "#9aa4b8", align = "center" },
        { type = "text", x = w / 2, y = h - 9,
          text = "edit the .lua file, right-click - Reload script",
          size = 9, color = "#5f6a7d", align = "center" },
    }
end

function W.on_tick(ms)
    angle = (ms or 0) / 400
end

function W.on_click(x, y, button)
    W.state.clicks = (W.state.clicks or 0) + 1
end

return W
