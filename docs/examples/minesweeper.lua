-- Minesweeper — a user Lua desktop widget for illogical-desktop.
--
-- Controls:
--   left click        reveal a cell (first click is always safe)
--   middle click      put / remove a flag
--   "Flag" button     flag mode: left click toggles flags
--   "New" button      new game
--
-- 9x9 board, 10 mines. The game (mines, revealed cells, flags, timer) is kept in
-- W.state, so it survives restarts and is copied when the widget is duplicated.

local W = { width = 270, height = 312, tick = 0 }

local SIZE = 9
local MINES = 10
local CELL = 24
local GRID_X = (W.width - SIZE * CELL) / 2
local GRID_Y = 76

local COLOR = {
    hidden = "#39404e",
    hiddenEdge = "rgba(255,255,255,0.08)",
    open = "#232730",
    openEdge = "rgba(255,255,255,0.03)",
    flag = "#ffd166",
    mine = "#ff6b6b",
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    button = "rgba(255,255,255,0.07)",
    buttonActive = "rgba(143,180,255,0.28)",
}
local NUMBER_COLORS = {
    "#7fb3ff", "#7bd389", "#ff8c8c", "#c792ea",
    "#ffb86c", "#6bd5e1", "#e0e0e0", "#a0a0a0",
}

local function fresh()
    return {
        mines = {},
        revealed = {},
        flags = {},
        generated = false,
        over = false,
        win = false,
        startTime = 0,
        elapsed = 0,
        flagMode = false,
    }
end

local function ensure_state()
    if type(W.state) ~= "table" then
        W.state = fresh()
    end
    local state = W.state
    state.mines = state.mines or {}
    state.revealed = state.revealed or {}
    state.flags = state.flags or {}
    state.generated = state.generated or false
    state.over = state.over or false
    state.win = state.win or false
    state.startTime = state.startTime or 0
    state.elapsed = state.elapsed or 0
    state.flagMode = state.flagMode or false
end

local function row_of(index)
    return math.floor((index - 1) / SIZE)
end

local function col_of(index)
    return (index - 1) % SIZE
end

local function neighbors(index)
    local row, col = row_of(index), col_of(index)
    local result = {}
    for dr = -1, 1 do
        for dc = -1, 1 do
            if not (dr == 0 and dc == 0) then
                local r, c = row + dr, col + dc
                if r >= 0 and r < SIZE and c >= 0 and c < SIZE then
                    result[#result + 1] = r * SIZE + c + 1
                end
            end
        end
    end
    return result
end

local function adjacent_mines(state, index)
    local count = 0
    for _, other in ipairs(neighbors(index)) do
        if state.mines[other] then
            count = count + 1
        end
    end
    return count
end

local function count_keys(table_value)
    local count = 0
    for _ in pairs(table_value) do
        count = count + 1
    end
    return count
end

local function generate(state, safe_index)
    local blocked = { [safe_index] = true }
    for _, index in ipairs(neighbors(safe_index)) do
        blocked[index] = true
    end

    local candidates = {}
    for index = 1, SIZE * SIZE do
        if not blocked[index] then
            candidates[#candidates + 1] = index
        end
    end

    for index = #candidates, 2, -1 do
        local swap = math.random(index)
        candidates[index], candidates[swap] = candidates[swap], candidates[index]
    end

    state.mines = {}
    for index = 1, math.min(MINES, #candidates) do
        state.mines[candidates[index]] = true
    end
    state.generated = true
    state.startTime = os.time()
    state.over = false
    state.win = false
    state.elapsed = 0
end

local function lose(state)
    state.over = true
    state.win = false
    state.elapsed = os.time() - state.startTime
    for index in pairs(state.mines) do
        state.revealed[index] = true
    end
end

local function check_win(state)
    if count_keys(state.revealed) == SIZE * SIZE - count_keys(state.mines) then
        state.over = true
        state.win = true
        state.elapsed = os.time() - state.startTime
    end
end

local function reveal(state, index)
    if state.flags[index] or state.revealed[index] or state.over then
        return
    end
    if state.mines[index] then
        lose(state)
        return
    end

    local stack = { index }
    while #stack > 0 do
        local current = table.remove(stack)
        if not state.revealed[current] and not state.flags[current] then
            state.revealed[current] = true
            if not state.mines[current] and adjacent_mines(state, current) == 0 then
                for _, other in ipairs(neighbors(current)) do
                    if not state.revealed[other] and not state.flags[other] then
                        stack[#stack + 1] = other
                    end
                end
            end
        end
    end
    check_win(state)
end

local function toggle_flag(state, index)
    if state.revealed[index] or state.over then
        return
    end
    if state.flags[index] then
        state.flags[index] = nil
    else
        state.flags[index] = true
    end
end

local function cell_at(x, y)
    local col = math.floor((x - GRID_X) / CELL)
    local row = math.floor((y - GRID_Y) / CELL)
    if col < 0 or col >= SIZE or row < 0 or row >= SIZE then
        return nil
    end
    return row * SIZE + col + 1
end

local function in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function flag_button()
    return W.width - 122, 38, 56, 22
end

local function new_button()
    return W.width - 60, 38, 46, 22
end

local function draw_flag(ops, cx, cy)
    ops[#ops + 1] = { type = "line", x1 = cx - 5, y1 = cy + 7, x2 = cx - 5, y2 = cy - 7,
        width = 2, color = COLOR.flag }
    ops[#ops + 1] = { type = "line", x1 = cx - 5, y1 = cy - 7, x2 = cx + 6, y2 = cy - 3,
        width = 2, color = COLOR.flag }
    ops[#ops + 1] = { type = "line", x1 = cx + 6, y1 = cy - 3, x2 = cx - 5, y2 = cy + 1,
        width = 2, color = COLOR.flag }
end

local function draw_mine(ops, cx, cy)
    ops[#ops + 1] = { type = "circle", x = cx, y = cy, r = 6, color = COLOR.mine }
    for angle = 0, 3 do
        local dx = math.cos(angle * math.pi / 2) * 9
        local dy = math.sin(angle * math.pi / 2) * 9
        ops[#ops + 1] = { type = "line", x1 = cx - dx, y1 = cy - dy, x2 = cx + dx, y2 = cy + dy,
            width = 1.5, color = COLOR.mine }
    end
    ops[#ops + 1] = { type = "circle", x = cx - 2, y = cy - 2, r = 1.5, color = "#ffffff" }
end

local function draw_cell(ops, state, index, x, y)
    local cx, cy = x + CELL / 2, y + CELL / 2
    if state.revealed[index] then
        ops[#ops + 1] = { type = "rect", x = x + 1, y = y + 1, w = CELL - 2, h = CELL - 2,
            radius = 3, color = COLOR.open, border = 1, borderColor = COLOR.openEdge }
        if state.mines[index] then
            draw_mine(ops, cx, cy)
        else
            local count = adjacent_mines(state, index)
            if count > 0 then
                ops[#ops + 1] = { type = "text", x = cx, y = cy, text = tostring(count),
                    size = 12, weight = 600, color = NUMBER_COLORS[count] or COLOR.text,
                    align = "center", valign = "middle" }
            end
        end
    else
        ops[#ops + 1] = { type = "rect", x = x + 1, y = y + 1, w = CELL - 2, h = CELL - 2,
            radius = 3, color = COLOR.hidden, border = 1, borderColor = COLOR.hiddenEdge }
        if state.flags[index] then
            draw_flag(ops, cx, cy)
        end
    end
end

function W.render(w, h)
    ensure_state()
    local state = W.state
    W.tick = (state.generated and not state.over) and 1000 or 0

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "rgba(18,18,21,0.80)", border = 1, borderColor = "rgba(255,255,255,0.10)" },
        { type = "text", x = 14, y = 24, text = "Minesweeper",
          size = 14, weight = 600, color = COLOR.text },
    }

    local mined = state.generated and count_keys(state.mines) or MINES
    local flags = count_keys(state.flags)
    local seconds = state.generated and (state.over and state.elapsed or (os.time() - state.startTime)) or 0
    ops[#ops + 1] = { type = "text", x = 14, y = 44,
        text = string.format("Mines: %d/%d   %02d:%02d", math.max(0, mined - flags), mined,
            math.floor(seconds / 60), seconds % 60),
        size = 11, color = COLOR.muted }

    local fx, fy, fw, fh = flag_button()
    ops[#ops + 1] = { type = "rect", x = fx, y = fy, w = fw, h = fh, radius = 7,
        color = state.flagMode and COLOR.buttonActive or COLOR.button,
        border = 1, borderColor = state.flagMode and COLOR.accent or "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = fx + fw / 2, y = fy + fh / 2, text = "Flag",
        size = 11, color = state.flagMode and COLOR.accent or COLOR.text,
        align = "center", valign = "middle" }

    local nx, ny, nw, nh = new_button()
    ops[#ops + 1] = { type = "rect", x = nx, y = ny, w = nw, h = nh, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = nx + nw / 2, y = ny + nh / 2, text = "New",
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    for index = 1, SIZE * SIZE do
        local row, col = row_of(index), col_of(index)
        draw_cell(ops, state, index, GRID_X + col * CELL, GRID_Y + row * CELL)
    end

    if state.over then
        ops[#ops + 1] = { type = "rect", x = GRID_X, y = GRID_Y, w = SIZE * CELL, h = SIZE * CELL,
            radius = 6, color = "rgba(10,10,14,0.68)" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL / 2 - 10,
            text = state.win and "You win!" or "Boom!",
            size = 26, weight = 700, color = state.win and "#8be28b" or COLOR.mine,
            align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL / 2 + 20,
            text = "Press New", size = 11, color = COLOR.muted, align = "center" }
    else
        local hint
        if state.flagMode then
            hint = "Flag mode: click a cell"
        elseif not state.generated then
            hint = "Click a cell to start"
        else
            hint = "Middle click flags a cell"
        end
        ops[#ops + 1] = { type = "text", x = w / 2, y = h - 8, text = hint,
            size = 9, color = COLOR.muted, align = "center" }
    end

    return ops
end

function W.on_click(x, y, button)
    ensure_state()
    local state = W.state

    local fx, fy, fw, fh = flag_button()
    if in_rect(x, y, fx, fy, fw, fh) then
        state.flagMode = not state.flagMode
        return
    end

    local nx, ny, nw, nh = new_button()
    if in_rect(x, y, nx, ny, nw, nh) then
        W.state = fresh()
        return
    end

    if state.over then
        return
    end

    local index = cell_at(x, y)
    if not index then
        return
    end

    if button == "middle" then
        toggle_flag(state, index)
        return
    end

    if state.flagMode then
        if state.revealed[index] then
            return
        end
        toggle_flag(state, index)
        return
    end

    if not state.generated then
        generate(state, index)
    end
    reveal(state, index)
end

return W
