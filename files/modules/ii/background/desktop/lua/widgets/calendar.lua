-- Built-in desktop widget: calendar (month / compact).

local W = { width = 380, height = 320, tick = 60000 }
local style = "month"

local TEXT = "#eef0f6"
local MUTED = "#b9bec9"
local ACCENT = "#8fb4ff"
local ON_ACCENT = "#10131a"

local WEEKDAYS = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }

local function card(ops, w, h)
    ops[#ops + 1] = { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
        color = "rgba(18,18,21,0.74)", border = 1, borderColor = "rgba(255,255,255,0.10)" }
end

function W.init(w, h, s)
    style = s or "month"
    if style == "compact" then
        W.width, W.height = 280, 120
    else
        W.width, W.height = 380, 320
    end
end

local function month_render(ops, w, h)
    local now = os.date("*t")
    local first = os.time({ year = now.year, month = now.month, day = 1, hour = 12 })
    local first_wday = os.date("*t", first).wday
    local offset = (first_wday + 5) % 7 -- Monday first
    local days = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0, hour = 12 })))

    ops[#ops + 1] = { type = "text", x = w / 2, y = 28,
        text = os.date("%B %Y", first), size = 18, weight = 600, color = TEXT, align = "center" }

    local grid_x = 16
    local grid_w = w - 32
    local cell_w = grid_w / 7

    for index, label in ipairs(WEEKDAYS) do
        ops[#ops + 1] = {
            type = "text", x = grid_x + (index - 0.5) * cell_w, y = 54,
            text = label, size = 10, color = MUTED, align = "center"
        }
    end

    local top = 68
    local cell_h = (h - top - 8) / 6
    for index = 0, 41 do
        local number = index - offset + 1
        local row = math.floor(index / 7)
        local column = index % 7
        local cx = grid_x + (column + 0.5) * cell_w
        local cy = top + (row + 0.5) * cell_h
        if number >= 1 and number <= days then
            local is_today = number == now.day
            if is_today then
                ops[#ops + 1] = { type = "circle", x = cx, y = cy, r = 13, color = ACCENT }
            end
            ops[#ops + 1] = {
                type = "text", x = cx, y = cy, text = tostring(number),
                size = 11, color = is_today and ON_ACCENT or TEXT,
                align = "center", valign = "middle"
            }
        end
    end
end

local function compact_render(ops, w, h)
    local now = os.date("*t")
    local today = os.time(now)
    ops[#ops + 1] = { type = "text", x = 26, y = h / 2, text = tostring(now.day),
        size = 48, weight = 600, color = TEXT, align = "center", valign = "middle" }
    ops[#ops + 1] = { type = "text", x = 84, y = h / 2 - 10,
        text = os.date("%A", today), size = 14, color = TEXT }
    ops[#ops + 1] = { type = "text", x = 84, y = h / 2 + 10,
        text = os.date("%B %Y", today), size = 12, color = MUTED }
end

function W.render(w, h)
    local ops = {}
    card(ops, w, h)
    if style == "compact" then
        compact_render(ops, w, h)
    else
        month_render(ops, w, h)
    end
    return ops
end

return W
