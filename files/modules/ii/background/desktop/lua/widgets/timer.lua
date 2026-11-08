-- Built-in desktop widget: timer / alarm (ring / pill).
-- The alarm icon opens GNOME Clocks.

local W = { width = 300, height = 330, tick = 0 }
local style = "ring"

local TEXT = "#eef0f6"
local MUTED = "#b9bec9"
local ACCENT = "#8fb4ff"

local function ensure_state()
    local state = W.state
    state.duration = state.duration or 300
    state.remaining = state.remaining or state.duration
    state.running = state.running or false
    state.endTime = state.endTime or 0
    if state.running and state.endTime <= os.time() then
        state.running = false
        state.remaining = 0
    end
end

local function card(ops, w, h)
    ops[#ops + 1] = { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
        color = "rgba(18,18,21,0.74)", border = 1, borderColor = "rgba(255,255,255,0.10)" }
end

local function remaining()
    local state = W.state
    if state.running then
        return math.max(0, state.endTime - os.time())
    end
    return math.max(0, state.remaining)
end

local function format_time(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function W.init(w, h, s)
    style = s or "ring"
    if style == "pill" then
        W.width, W.height = 380, 120
    else
        W.width, W.height = 300, 330
    end
    ensure_state()
end

local function layout(w, h)
    if style == "pill" then
        return {
            { id = "add",   x = 120, y = 45, w = 38, h = 30, label = "+5" },
            { id = "start", x = 163, y = 45, w = 56, h = 30, label = desktop.tr("Start") },
            { id = "pause", x = 224, y = 45, w = 56, h = 30, label = desktop.tr("Pause") },
            { id = "reset", x = 285, y = 45, w = 56, h = 30, label = desktop.tr("Reset") },
            { id = "alarm", x = 346, y = 45, w = 30, h = 30, icon = true },
        }
    end
    return {
        { id = "add",   x = 6,   y = 292, w = 44, h = 30, label = "+1" },
        { id = "start", x = 56,  y = 292, w = 60, h = 30, label = desktop.tr("Start") },
        { id = "pause", x = 122, y = 292, w = 60, h = 30, label = desktop.tr("Pause") },
        { id = "reset", x = 188, y = 292, w = 60, h = 30, label = desktop.tr("Reset") },
        { id = "alarm", x = 254, y = 292, w = 34, h = 30, icon = true },
    }
end

local function draw_button(ops, button)
    ops[#ops + 1] = { type = "rect", x = button.x, y = button.y, w = button.w, h = button.h,
        radius = 8, color = "rgba(255,255,255,0.07)" }
    if button.icon then
        local cx, cy = button.x + button.w / 2, button.y + button.h / 2
        ops[#ops + 1] = { type = "circle", x = cx, y = cy + 1, r = 6, border = 1.5, borderColor = MUTED }
        ops[#ops + 1] = { type = "line", x1 = cx, y1 = cy + 1, x2 = cx, y2 = cy - 2, width = 1.5, color = MUTED }
        ops[#ops + 1] = { type = "line", x1 = cx, y1 = cy + 1, x2 = cx + 3, y2 = cy + 3, width = 1.5, color = MUTED }
    else
        ops[#ops + 1] = { type = "text", x = button.x + button.w / 2, y = button.y + button.h / 2,
            text = button.label, size = 11, color = TEXT, align = "center", valign = "middle" }
    end
end

function W.render(w, h)
    ensure_state()
    local state = W.state
    W.tick = state.running and 250 or 0

    local ops = {}
    card(ops, w, h)
    local seconds = remaining()

    if style == "pill" then
        ops[#ops + 1] = { type = "text", x = 20, y = h / 2, text = format_time(seconds),
            size = 30, weight = 600, color = TEXT, valign = "middle" }
    else
        local cx, cy = w / 2, 150
        local radius = 116
        local progress = state.duration > 0 and math.max(0, math.min(1, seconds / state.duration)) or 0
        ops[#ops + 1] = { type = "arc", x = cx, y = cy, r = radius,
            from = 0, to = math.pi * 2, width = 8, color = "rgba(255,255,255,0.12)" }
        if progress > 0 then
            ops[#ops + 1] = { type = "arc", x = cx, y = cy, r = radius,
                from = -math.pi / 2, to = -math.pi / 2 + math.pi * 2 * progress,
                width = 8, color = ACCENT }
        end
        ops[#ops + 1] = { type = "text", x = cx, y = cy, text = format_time(seconds),
            size = 30, weight = 600, color = TEXT, align = "center", valign = "middle" }
    end

    for _, button in ipairs(layout(w, h)) do
        draw_button(ops, button)
    end
    return ops
end

function W.on_click(x, y)
    local state = W.state
    for _, button in ipairs(layout(W.width, W.height)) do
        if x >= button.x and x <= button.x + button.w and y >= button.y and y <= button.y + button.h then
            if button.id == "start" then
                local seconds = state.remaining
                if seconds <= 0 then
                    seconds = state.duration
                end
                state.endTime = os.time() + seconds
                state.running = true
            elseif button.id == "pause" then
                if state.running then
                    state.remaining = remaining()
                end
                state.running = false
            elseif button.id == "reset" then
                state.running = false
                state.remaining = state.duration
            elseif button.id == "add" then
                local add = style == "pill" and 300 or 60
                state.duration = state.duration + add
                if state.running then
                    state.endTime = state.endTime + add
                else
                    state.remaining = state.remaining + add
                end
            elseif button.id == "alarm" then
                desktop.spawn("gnome-clocks")
            end
            return
        end
    end
end

function W.on_tick()
    local state = W.state
    if state.running and os.time() >= state.endTime then
        state.running = false
        state.remaining = 0
        desktop.notify(desktop.tr("Timer"), desktop.tr("Time is up"))
    end
end

return W
