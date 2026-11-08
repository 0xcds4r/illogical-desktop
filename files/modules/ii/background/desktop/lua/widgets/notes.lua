-- Built-in desktop widget: sticky note (yellow / pink / blue / green).
-- The note text is edited with a real text input provided by the host.

local W = { width = 280, height = 240, tick = 0, rotation = 0 }
-- The card is inset so the small tilt never clips its corners on the canvas.
local INSET = 10
local style = "yellow"

local COLORS = {
    yellow = "#F6E39B",
    pink = "#F6C6D0",
    blue = "#BFD8F2",
    green = "#CBE7C4",
}

local function note_color()
    return COLORS[style] or COLORS.yellow
end

function W.init(w, h, s, id)
    style = s or "yellow"
    W.width, W.height = 280, 240
    -- Same slight, stable tilt for every note, derived from its instance id.
    local seed = #(id or "")
    W.rotation = (seed * 7) % 5 - 2
end

function W.render(w, h)
    local left = INSET
    local top = INSET
    local width = w - INSET * 2
    local height = h - INSET * 2
    local ops = {
        { type = "rect", x = left, y = top, w = width, h = height, radius = 6,
          color = note_color(), border = 1, borderColor = "rgba(0,0,0,0.15)" },
        { type = "rect", x = left + 6, y = top + 6, w = width - 12, h = height - 12, radius = 4,
          border = 1, borderColor = "rgba(0,0,0,0.06)" },
        { type = "input", key = "note", x = left + 16, y = top + 44,
          w = width - 32, h = height - 60,
          text = W.state.text or "", size = 12, color = "#2b2b2b",
          family = "sans-serif", multiline = true,
          selectionColor = "#8a7a3a", selectedTextColor = "#ffffff" },
    }
    return ops
end

function W.on_text(key, text)
    if key == "note" then
        W.state.text = text
    end
end

return W
