-- Minimal example widget for the illogical-desktop Lua API.
-- Copy to <desktop folder>/.widgets/hello.lua and add it from
-- Settings -> Widgets -> Custom widgets.

local W = {
    width = 280,
    height = 140,
    tick = 50, -- animate
}

local phase = 0

function W.render(w, h)
    local clicks = (W.state.clicks or 0)
    local glow = 0.5 + 0.5 * math.sin(phase)
    local radius = 22 + 4 * glow
    return {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 16,
          color = "rgba(18,18,21,0.74)", border = 1,
          borderColor = "rgba(255,255,255,0.10)" },
        { type = "circle", x = w / 2, y = 54, r = radius,
          color = string.format("#%02x%02x%02x",
              math.floor(120 + 60 * glow), math.floor(150 + 40 * glow), 255) },
        { type = "text", x = w / 2, y = h - 46, text = "Hello, desktop",
          size = 16, color = "#ffffff", align = "center" },
        { type = "text", x = w / 2, y = h - 22,
          text = "clicks: " .. clicks, size = 12, color = "#9aa4b8", align = "center" },
    }
end

function W.on_tick(ms)
    phase = (ms or 0) / 400
end

function W.on_click()
    W.state.clicks = (W.state.clicks or 0) + 1
end

return W
