-- Built-in desktop widget: mini paint (paper / board).
-- Strokes are kept in the widget's persistent state, so drawings survive
-- restarts and are copied together with the widget.

local W = { width = 380, height = 300, tick = 0 }
local style = "paper"

local drawing = false
local drew = false
local current = nil

local PAPER = { background = "#f5f2ea", ink = { "#222222", "#d64545", "#d9a400", "#3d8b40", "#2f6fd0" } }
local BOARD = { background = "#20252b", ink = { "#ffffff", "#ff6b6b", "#ffd166", "#7bd389", "#6bb6ff" } }

local function theme()
    return style == "board" and BOARD or PAPER
end

local function ensure_state()
    W.state.strokes = W.state.strokes or {}
    W.state.color = W.state.color or 1
end

function W.init(w, h, s)
    style = s or "paper"
    W.width, W.height = 380, 300
    ensure_state()
end

local function canvas_rect(w, h)
    return 8, 44, w - 16, h - 44 - 46
end

local function clear_rect(w, h)
    return w - 74, h - 34, 64, 24
end

local function palette_positions(w, h)
    local positions = {}
    for index = 1, 5 do
        positions[index] = { x = 18 + (index - 1) * 24, y = h - 22, r = 9 }
    end
    return positions
end

function W.render(w, h)
    ensure_state()
    local colors = theme()
    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 16,
          color = colors.background, border = 1, borderColor = "rgba(0,0,0,0.2)" },
    }

    for _, stroke in ipairs(W.state.strokes) do
        for index = 2, #stroke.points do
            local a = stroke.points[index - 1]
            local b = stroke.points[index]
            ops[#ops + 1] = { type = "line", x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y,
                width = stroke.width or 3, color = stroke.color, lineCap = "round" }
        end
    end

    if current and #current.points > 1 then
        for index = 2, #current.points do
            local a = current.points[index - 1]
            local b = current.points[index]
            ops[#ops + 1] = { type = "line", x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y,
                width = 3, color = current.color, lineCap = "round" }
        end
    end

    for index, position in ipairs(palette_positions(w, h)) do
        ops[#ops + 1] = { type = "circle", x = position.x, y = position.y, r = position.r,
            color = colors.ink[index], border = (W.state.color == index) and 2 or 1,
            borderColor = style == "board" and "rgba(255,255,255,0.6)" or "rgba(0,0,0,0.4)" }
    end

    local clear_x = clear_rect(w, h)
    ops[#ops + 1] = { type = "rect", x = clear_x, y = h - 34, w = 64, h = 24, radius = 8,
        border = 1, borderColor = style == "board" and "rgba(255,255,255,0.25)" or "rgba(0,0,0,0.2)" }
    ops[#ops + 1] = { type = "text", x = clear_x + 32, y = h - 22,
        text = desktop.tr("Clear"), size = 11,
        color = style == "board" and "#ffffff" or "#222222", align = "center", valign = "middle" }

    return ops
end

function W.on_press(x, y)
    ensure_state()
    local w, h = W.width, W.height
    local cx, cy, cw, ch = canvas_rect(w, h)
    if x >= cx and x <= cx + cw and y >= cy and y <= cy + ch then
        current = { color = theme().ink[W.state.color], points = { { x = x, y = y } } }
        drawing = true
    end
end

function W.on_move(x, y)
    if not drawing or not current then
        return
    end
    local points = current.points
    local last = points[#points]
    if math.abs(x - last.x) + math.abs(y - last.y) >= 2 then
        points[#points + 1] = { x = x, y = y }
    end
end

function W.on_release()
    drew = false
    if drawing and current then
        W.state.strokes[#W.state.strokes + 1] = { color = current.color, width = 3, points = current.points }
        drew = true
    end
    drawing = false
    current = nil
end

function W.on_click(x, y)
    ensure_state()
    if drew then
        drew = false
        return
    end
    local w, h = W.width, W.height

    local bx, by, bw, bh = clear_rect(w, h)
    if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
        W.state.strokes = {}
        return
    end

    for index, position in ipairs(palette_positions(w, h)) do
        local dx, dy = x - position.x, y - position.y
        if dx * dx + dy * dy <= (position.r + 4) ^ 2 then
            W.state.color = index
            return
        end
    end
end

return W
