-- Snake — a user Lua desktop widget for illogical-desktop.
--
-- Controls:
--   click on the board        steer towards the clicked side of the head
--   arrow buttons under board steer
--   "Start"/"Pause" button    start or pause
--   "New" button              new game
--
-- The score and best score persist; a game in progress survives a shell restart.

local W = { width = 280, height = 360, tick = 0 }

local SIZE = 12
local CELL = 20
local GRID_X = (W.width - SIZE * CELL) / 2 -- 20
local GRID_Y = 70
local BASE_SPEED = 150

local COLOR = {
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    snake = "#7bd389",
    head = "#b9f2a4",
    eye = "#1d2a1d",
    food = "#ff6b6b",
    board = "rgba(0,0,0,0.24)",
    button = "rgba(255,255,255,0.07)",
}

local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local STEP = {
    up = { x = 0, y = -1 },
    down = { x = 0, y = 1 },
    left = { x = -1, y = 0 },
    right = { x = 1, y = 0 },
}

local function random_food(snake)
    local occupied = {}
    for _, segment in ipairs(snake) do
        occupied[segment.x * SIZE + segment.y] = true
    end
    local free = {}
    for x = 0, SIZE - 1 do
        for y = 0, SIZE - 1 do
            if not occupied[x * SIZE + y] then
                free[#free + 1] = { x = x, y = y }
            end
        end
    end
    if #free == 0 then
        return { x = 0, y = 0 }
    end
    return free[math.random(#free)]
end

local function fresh(best)
    local snake = {
        { x = 5, y = 6 },
        { x = 4, y = 6 },
        { x = 3, y = 6 },
    }
    return {
        snake = snake,
        dir = "right",
        food = random_food(snake),
        running = false,
        over = false,
        score = 0,
        best = best or 0,
        speed = BASE_SPEED,
    }
end

local function ensure_state()
    if type(W.state) ~= "table" then
        W.state = fresh(0)
    end
    local state = W.state
    if type(state.snake) ~= "table" or #state.snake == 0 then
        W.state = fresh(state.best or 0)
        return
    end
    state.food = state.food or random_food(state.snake)
    state.dir = state.dir or "right"
    state.running = state.running or false
    state.over = state.over or false
    state.score = state.score or 0
    state.best = state.best or 0
    state.speed = state.speed or BASE_SPEED
end

local function occupied(state, x, y)
    if x < 0 or y < 0 or x >= SIZE or y >= SIZE then
        return true
    end
    for _, segment in ipairs(state.snake) do
        if segment.x == x and segment.y == y then
            return true
        end
    end
    return false
end

local function tick(state)
    if not state.running or state.over then
        return
    end
    local step = STEP[state.dir] or STEP.right
    local head = state.snake[1]
    local next_cell = { x = head.x + step.x, y = head.y + step.y }

    if occupied(state, next_cell.x, next_cell.y) then
        -- Moving into the tail is allowed when the tail moves away this tick.
        local tail = state.snake[#state.snake]
        local eats = next_cell.x == state.food.x and next_cell.y == state.food.y
        if eats or not (tail and next_cell.x == tail.x and next_cell.y == tail.y) then
            state.over = true
            state.running = false
            if state.score > state.best then
                state.best = state.score
            end
            return
        end
    end

    table.insert(state.snake, 1, next_cell)
    if next_cell.x == state.food.x and next_cell.y == state.food.y then
        state.score = state.score + 1
        state.best = math.max(state.best, state.score)
        state.speed = math.max(80, BASE_SPEED - state.score * 5)
        state.food = random_food(state.snake)
    else
        table.remove(state.snake)
    end
end

local function steer(state, direction)
    if not state.running or state.over then
        return
    end
    if OPPOSITE[state.dir] == direction then
        return
    end
    state.dir = direction
end

local function cell_at(x, y)
    local col = math.floor((x - GRID_X) / CELL)
    local row = math.floor((y - GRID_Y) / CELL)
    if col < 0 or col >= SIZE or row < 0 or row >= SIZE then
        return nil
    end
    return col, row
end

local function dpad()
    local width, gap = 40, 8
    local total = width * 4 + gap * 3
    local x0 = (W.width - total) / 2
    local y = 320
    return {
        { dir = "left",  x = x0,               y = y, w = width, h = 30, label = "<" },
        { dir = "up",    x = x0 + width + gap, y = y, w = width, h = 30, label = "^" },
        { dir = "down",  x = x0 + (width + gap) * 2, y = y, w = width, h = 30, label = "v" },
        { dir = "right", x = x0 + (width + gap) * 3, y = y, w = width, h = 30, label = ">" },
    }
end

local function play_button()
    return W.width - 128, 38, 64, 22
end

local function new_button()
    return W.width - 58, 38, 46, 22
end

local function in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function W.init(w, h, style, id)
    math.randomseed(os.time() + #(id or ""))
end

function W.render(w, h)
    ensure_state()
    local state = W.state
    W.tick = (state.running and not state.over) and state.speed or 0

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "rgba(18,18,21,0.82)", border = 1, borderColor = "rgba(255,255,255,0.10)" },
        { type = "text", x = 16, y = 24, text = "Snake", size = 15, weight = 600, color = COLOR.text },
        { type = "text", x = 16, y = 46, text = "Score " .. state.score .. "   Best " .. state.best,
          size = 11, color = COLOR.muted },
        { type = "rect", x = GRID_X - 4, y = GRID_Y - 4, w = SIZE * CELL + 8, h = SIZE * CELL + 8,
          radius = 8, color = COLOR.board, border = 1, borderColor = "rgba(255,255,255,0.06)" },
    }

    local play = { x = w - 128, y = 38, w = 64, h = 22 }
    ops[#ops + 1] = { type = "rect", x = play.x, y = play.y, w = play.w, h = play.h, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = play.x + play.w / 2, y = play.y + play.h / 2,
        text = state.over and "Again" or (state.running and "Pause" or "Start"),
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    local new = { x = w - 58, y = 38, w = 46, h = 22 }
    ops[#ops + 1] = { type = "rect", x = new.x, y = new.y, w = new.w, h = new.h, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = new.x + new.w / 2, y = new.y + new.h / 2, text = "New",
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    -- food
    ops[#ops + 1] = { type = "circle", x = GRID_X + state.food.x * CELL + CELL / 2,
        y = GRID_Y + state.food.y * CELL + CELL / 2, r = 7, color = COLOR.food }
    ops[#ops + 1] = { type = "circle", x = GRID_X + state.food.x * CELL + CELL / 2 - 2,
        y = GRID_Y + state.food.y * CELL + CELL / 2 - 3, r = 2,
        color = "rgba(255,255,255,0.65)" }

    -- snake
    for index = #state.snake, 1, -1 do
        local segment = state.snake[index]
        local x = GRID_X + segment.x * CELL
        local y = GRID_Y + segment.y * CELL
        ops[#ops + 1] = { type = "rect", x = x + 1, y = y + 1, w = CELL - 2, h = CELL - 2,
            radius = 5, color = index == 1 and COLOR.head or COLOR.snake }
    end
    local head = state.snake[1]
    if head then
        local hx = GRID_X + head.x * CELL + CELL / 2
        local hy = GRID_Y + head.y * CELL + CELL / 2
        ops[#ops + 1] = { type = "circle", x = hx - 3, y = hy - 2, r = 1.7, color = COLOR.eye }
        ops[#ops + 1] = { type = "circle", x = hx + 3, y = hy - 2, r = 1.7, color = COLOR.eye }
    end

    if state.over then
        ops[#ops + 1] = { type = "rect", x = GRID_X, y = GRID_Y, w = SIZE * CELL, h = SIZE * CELL,
            radius = 6, color = "rgba(10,10,14,0.68)" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL / 2 - 12,
            text = "Game over", size = 22, weight = 700, color = COLOR.food,
            align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL / 2 + 16,
            text = "Score " .. state.score .. "  -  Best " .. state.best,
            size = 12, color = COLOR.text, align = "center" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL / 2 + 36,
            text = "Press Again or New", size = 10, color = COLOR.muted, align = "center" }
    elseif not state.running then
        ops[#ops + 1] = { type = "text", x = w / 2, y = GRID_Y + SIZE * CELL - 14,
            text = "Press Start", size = 11, color = COLOR.muted,
            align = "center", valign = "middle" }
    end

    for _, button in ipairs(dpad()) do
        ops[#ops + 1] = { type = "rect", x = button.x, y = button.y, w = button.w, h = button.h,
            radius = 7, color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
        ops[#ops + 1] = { type = "text", x = button.x + button.w / 2, y = button.y + button.h / 2,
            text = button.label, size = 14, weight = 600, color = COLOR.text,
            align = "center", valign = "middle" }
    end

    return ops
end

function W.on_tick()
    ensure_state()
    tick(W.state)
end

function W.on_click(x, y, button)
    ensure_state()
    local state = W.state

    local px, py, pw, ph = play_button()
    if in_rect(x, y, px, py, pw, ph) then
        if state.over then
            W.state = fresh(state.best)
            W.state.running = true
        else
            state.running = not state.running
        end
        return
    end

    local nx, ny, nw, nh = new_button()
    if in_rect(x, y, nx, ny, nw, nh) then
        W.state = fresh(state.best)
        return
    end

    for _, button in ipairs(dpad()) do
        if in_rect(x, y, button.x, button.y, button.w, button.h) then
            steer(state, button.dir)
            return
        end
    end

    local col, row = cell_at(x, y)
    if col and state.running and not state.over then
        local head = state.snake[1]
        local dx, dy = col - head.x, row - head.y
        if math.abs(dx) >= math.abs(dy) then
            if dx ~= 0 then
                steer(state, dx > 0 and "right" or "left")
            end
        elseif dy ~= 0 then
            steer(state, dy > 0 and "down" or "up")
        end
    end
end

return W
