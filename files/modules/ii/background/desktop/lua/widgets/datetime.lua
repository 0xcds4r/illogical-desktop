-- Built-in desktop widget: date and time (stacked / inline).

local W = { width = 320, height = 130, tick = 1000 }
local style = "stacked"

local TEXT = "#eef0f6"
local MUTED = "#b9bec9"

local function card(ops, w, h)
    ops[#ops + 1] = { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
        color = "rgba(18,18,21,0.74)", border = 1, borderColor = "rgba(255,255,255,0.10)" }
end

function W.init(w, h, s)
    style = s or "stacked"
    if style == "inline" then
        W.width, W.height = 420, 90
    else
        W.width, W.height = 320, 130
    end
end

function W.render(w, h)
    local now = os.date("*t")
    local today = os.time(now)
    local time = string.format("%02d:%02d", now.hour, now.min)
    local ops = {}
    card(ops, w, h)

    if style == "inline" then
        ops[#ops + 1] = { type = "text", x = w / 2 - 92, y = h / 2, text = time,
            size = 34, weight = 600, color = TEXT, align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2 + 60, y = h / 2,
            text = os.date("%a, %d %b %Y", today), size = 13, color = MUTED,
            align = "center", valign = "middle" }
    else
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 - 8, text = time,
            size = 42, weight = 600, color = TEXT, align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 + 28,
            text = os.date("%A, %d %B %Y", today), size = 12, color = MUTED, align = "center" }
    end
    return ops
end

return W
