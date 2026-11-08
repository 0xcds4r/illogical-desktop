-- Built-in desktop widget: clock (digital / analog / minimal).

local W = { width = 300, height = 130, tick = 1000 }
local style = "digital"

local TEXT = "#eef0f6"
local MUTED = "#b9bec9"
local ACCENT = "#8fb4ff"

local function hex(r, g, b)
    return string.format("#%02x%02x%02x", math.floor(r), math.floor(g), math.floor(b))
end

local function card(ops, w, h)
    ops[#ops + 1] = { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
        color = "rgba(18,18,21,0.74)", border = 1, borderColor = "rgba(255,255,255,0.10)" }
end

function W.init(w, h, s)
    style = s or "digital"
    if style == "analog" then
        W.width, W.height = 220, 220
    elseif style == "minimal" then
        W.width, W.height = 280, 96
    else
        W.width, W.height = 300, 130
    end
end

local function analog(ops, w, h, now)
    local cx, cy = w / 2, h / 2
    local radius = math.min(w, h) / 2 - 12
    ops[#ops + 1] = { type = "circle", x = cx, y = cy, r = radius,
        color = "rgba(24,24,28,0.92)", border = 2, borderColor = "rgba(255,255,255,0.22)" }

    for index = 0, 11 do
        local angle = index / 12 * math.pi * 2
        local inner = radius - ((index % 3 == 0) and 18 or 11)
        local outer = radius - 5
        ops[#ops + 1] = {
            type = "line",
            x1 = cx + math.sin(angle) * inner, y1 = cy - math.cos(angle) * inner,
            x2 = cx + math.sin(angle) * outer, y2 = cy - math.cos(angle) * outer,
            width = (index % 3 == 0) and 3 or 1.5,
            color = (index % 3 == 0) and "rgba(255,255,255,0.85)" or "rgba(255,255,255,0.42)"
        }
    end

    local hours = (now.hour % 12) + now.min / 60
    local minutes = now.min + now.sec / 60
    local function hand(angle, length, width, color)
        ops[#ops + 1] = {
            type = "line", x1 = cx, y1 = cy,
            x2 = cx + math.sin(angle) * length, y2 = cy - math.cos(angle) * length,
            width = width, color = color
        }
    end
    hand(hours / 12 * math.pi * 2, radius * 0.5, 5, "#ffffff")
    hand(minutes / 60 * math.pi * 2, radius * 0.72, 3, "rgba(255,255,255,0.85)")
    hand(now.sec / 60 * math.pi * 2, radius * 0.82, 1.5, ACCENT)

    ops[#ops + 1] = { type = "circle", x = cx, y = cy, r = 4, color = ACCENT }
end

function W.render(w, h)
    local now = os.date("*t")
    local ops = {}
    card(ops, w, h)

    if style == "analog" then
        analog(ops, w, h, now)
        return ops
    end

    local time = string.format("%02d:%02d", now.hour, now.min)
    if style == "minimal" then
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2, text = time,
            size = 44, weight = 600, color = TEXT, align = "center", valign = "middle" }
    else
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 - 8, text = time,
            size = 46, weight = 600, color = TEXT, align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 + 27,
            text = os.date("%A, %d %B", os.time(now)),
            size = 12, color = MUTED, align = "center" }
    end
    return ops
end

return W
