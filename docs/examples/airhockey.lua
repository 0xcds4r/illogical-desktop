-- Air Hockey — a mouse-driven desktop widget for illogical-desktop.
--
-- Move the mouse inside the table to control the blue paddle; keyboard arrows or
-- WASD work as a fallback (click the table first to give it keyboard focus).
-- First to 7 goals wins the match.
--
-- Controls:
--   mouse hover        move the paddle
--   arrows / WASD      move the paddle (keyboard fallback)
--   Space              pause / resume
--   Enter / R          new match
--   New button         new match
--
-- Match wins are stored in the widget state; the live match is kept in memory.

local W = { width = 320, height = 460, tick = 0 }

local TABLE = { x = 20, y = 68, w = 280, h = 340 }
local GOAL_W = 96
local PADDLE_R = 15
local PUCK_R = 8
local WIN_SCORE = 7
local MAX_SPEED = 980
local KEY_SPEED = 560
local AI_SPEED = 330

local COLOR = {
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    button = "rgba(255,255,255,0.07)",
    ice = "#dce8f2",
    iceEdge = "#b9cbdb",
    centerLine = "#8fa6b8",
    goal = "#30465c",
    player = "#3f7fd9",
    playerLight = "#8ab6ff",
    ai = "#c0392b",
    aiLight = "#ff9d8f",
    puck = "#20242b",
    wins = "#ffd166",
}

local held = {}
local game = nil
local lastMs = nil
local mouse_active = false

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function ensure_state()
    if type(W.state) ~= "table" then
        W.state = {}
    end
    W.state.wins = W.state.wins or 0
end

local function new_match(run)
    game = {
        puck = { x = TABLE.x + TABLE.w / 2, y = TABLE.y + TABLE.h / 2, vx = 0, vy = 0 },
        player = { x = TABLE.x + TABLE.w / 2, y = TABLE.y + TABLE.h - 52, vx = 0, vy = 0 },
        ai = { x = TABLE.x + TABLE.w / 2, y = TABLE.y + 52, vx = 0, vy = 0 },
        playerScore = 0,
        aiScore = 0,
        running = run or false,
        over = false,
        serveTimer = 0.8,
        message = "",
        trail = {},
        aiClock = 0,
    }
    lastMs = nil
end

local function ensure_match()
    if not game then
        new_match(false)
    end
end

local function clamp_player()
    game.player.x = clamp(game.player.x, TABLE.x + PADDLE_R, TABLE.x + TABLE.w - PADDLE_R)
    game.player.y = clamp(game.player.y, TABLE.y + TABLE.h / 2 + PADDLE_R,
        TABLE.y + TABLE.h - PADDLE_R)
end

local function clamp_ai()
    game.ai.x = clamp(game.ai.x, TABLE.x + PADDLE_R, TABLE.x + TABLE.w - PADDLE_R)
    game.ai.y = clamp(game.ai.y, TABLE.y + PADDLE_R, TABLE.y + TABLE.h / 2 - PADDLE_R)
end

local function serve()
    local puck = game.puck
    puck.x, puck.y = TABLE.x + TABLE.w / 2, TABLE.y + TABLE.h / 2
    local direction = math.random() < 0.5 and 1 or -1
    puck.vx = (math.random() - 0.5) * 280
    puck.vy = direction * (180 + math.random() * 90)
    game.trail = {}
    lastMs = nil
end

local function score_point(who)
    if who == "player" then
        game.playerScore = game.playerScore + 1
        game.message = "Goal!"
    else
        game.aiScore = game.aiScore + 1
        game.message = "CPU scores"
    end

    if game.playerScore >= WIN_SCORE or game.aiScore >= WIN_SCORE then
        game.over = true
        game.running = false
        if game.playerScore > game.aiScore then
            W.state.wins = (W.state.wins or 0) + 1
        end
        return
    end

    game.puck.x, game.puck.y = TABLE.x + TABLE.w / 2, TABLE.y + TABLE.h / 2
    game.puck.vx, game.puck.vy = 0, 0
    game.player.x = TABLE.x + TABLE.w / 2
    game.player.y = TABLE.y + TABLE.h - 52
    game.ai.x = TABLE.x + TABLE.w / 2
    game.ai.y = TABLE.y + 52
    game.serveTimer = 0.8
    game.trail = {}
    lastMs = nil
end

local function collide_paddle(paddle)
    local puck = game.puck
    local dx, dy = puck.x - paddle.x, puck.y - paddle.y
    local min_dist = PADDLE_R + PUCK_R
    local dist_sq = dx * dx + dy * dy
    if dist_sq >= min_dist * min_dist or dist_sq < 0.0001 then
        return
    end

    local dist = math.sqrt(dist_sq)
    local nx, ny = dx / dist, dy / dist
    puck.x = paddle.x + nx * (min_dist + 0.05)
    puck.y = paddle.y + ny * (min_dist + 0.05)

    local rel = (puck.vx - paddle.vx) * nx + (puck.vy - paddle.vy) * ny
    if rel < 0 then
        puck.vx = puck.vx - 2 * rel * nx
        puck.vy = puck.vy - 2 * rel * ny
    end
    puck.vx = puck.vx + paddle.vx * 0.35
    puck.vy = puck.vy + paddle.vy * 0.35

    local speed = math.sqrt(puck.vx * puck.vx + puck.vy * puck.vy)
    if speed > MAX_SPEED then
        puck.vx, puck.vy = puck.vx / speed * MAX_SPEED, puck.vy / speed * MAX_SPEED
    elseif speed < 120 then
        puck.vx, puck.vy = nx * 120, ny * 120
    end
end

local function physics(dt)
    local puck = game.puck
    local goal_left = TABLE.x + (TABLE.w - GOAL_W) / 2
    local goal_right = goal_left + GOAL_W

    puck.x = puck.x + puck.vx * dt
    puck.y = puck.y + puck.vy * dt
    puck.vx = puck.vx * (1 - 0.7 * dt)
    puck.vy = puck.vy * (1 - 0.7 * dt)

    if puck.x < TABLE.x + PUCK_R then
        puck.x = TABLE.x + PUCK_R
        puck.vx = math.abs(puck.vx) * 0.92
    elseif puck.x > TABLE.x + TABLE.w - PUCK_R then
        puck.x = TABLE.x + TABLE.w - PUCK_R
        puck.vx = -math.abs(puck.vx) * 0.92
    end

    if puck.y < TABLE.y + PUCK_R then
        if puck.x > goal_left and puck.x < goal_right then
            score_point("player")
            return
        end
        puck.y = TABLE.y + PUCK_R
        puck.vy = math.abs(puck.vy) * 0.92
    elseif puck.y > TABLE.y + TABLE.h - PUCK_R then
        if puck.x > goal_left and puck.x < goal_right then
            score_point("ai")
            return
        end
        puck.y = TABLE.y + TABLE.h - PUCK_R
        puck.vy = -math.abs(puck.vy) * 0.92
    end

    collide_paddle(game.player)
    collide_paddle(game.ai)

    game.trail[#game.trail + 1] = { x = puck.x, y = puck.y }
    if #game.trail > 6 then
        table.remove(game.trail, 1)
    end
end

local function update_ai(dt)
    local ai = game.ai
    local puck = game.puck
    local target_x = puck.x + puck.vx * 0.18
    local target_y
    if puck.y < TABLE.y + TABLE.h * 0.5 then
        target_y = puck.y - 22
    else
        target_y = TABLE.y + 72
    end
    target_x = clamp(target_x, TABLE.x + PADDLE_R, TABLE.x + TABLE.w - PADDLE_R)
    target_y = clamp(target_y, TABLE.y + PADDLE_R, TABLE.y + TABLE.h / 2 - PADDLE_R)

    local old_x, old_y = ai.x, ai.y
    local dx, dy = target_x - ai.x, target_y - ai.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > 1 then
        local step = math.min(distance, AI_SPEED * dt)
        ai.x = ai.x + dx / distance * step
        ai.y = ai.y + dy / distance * step
    end
    ai.vx = (ai.x - old_x) / math.max(dt, 0.001)
    ai.vy = (ai.y - old_y) / math.max(dt, 0.001)
end

local function update_player(dt)
    local player = game.player
    local old_x, old_y = player.x, player.y
    local move_x, move_y = 0, 0
    if held.left or held.a then move_x = move_x - 1 end
    if held.right or held.d then move_x = move_x + 1 end
    if held.up or held.w then move_y = move_y - 1 end
    if held.down or held.s then move_y = move_y + 1 end

    if move_x ~= 0 or move_y ~= 0 then
        local length = math.sqrt(move_x * move_x + move_y * move_y)
        player.x = player.x + move_x / length * KEY_SPEED * dt
        player.y = player.y + move_y / length * KEY_SPEED * dt
        mouse_active = false
        clamp_player()
    end

    player.vx = (player.x - old_x) / math.max(dt, 0.001)
    player.vy = (player.y - old_y) / math.max(dt, 0.001)
end

local function update(dt)
    if not game or game.over then
        return
    end
    game.aiClock = game.aiClock + dt
    update_player(dt)
    update_ai(dt)

    if game.serveTimer > 0 then
        game.serveTimer = game.serveTimer - dt
        if game.serveTimer <= 0 then
            serve()
        end
        return
    end

    -- Two substeps keep the puck from tunnelling through a paddle at high speed.
    physics(dt / 2)
    if game.over then return end
    physics(dt / 2)
end

local function slot_new_button()
    return W.width - 62, 38, 48, 22
end

local function in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function draw_table(ops)
    ops[#ops + 1] = { type = "rect", x = TABLE.x, y = TABLE.y, w = TABLE.w, h = TABLE.h,
        radius = 14, color = COLOR.ice, border = 3, borderColor = COLOR.iceEdge }

    local mid_y = TABLE.y + TABLE.h / 2
    for x = TABLE.x + 16, TABLE.x + TABLE.w - 16, 34 do
        ops[#ops + 1] = { type = "line", x1 = x, y1 = mid_y, x2 = x + 16, y2 = mid_y,
            width = 2, color = COLOR.centerLine }
    end
    ops[#ops + 1] = { type = "circle", x = TABLE.x + TABLE.w / 2, y = mid_y, r = 44,
        border = 2, borderColor = COLOR.centerLine }

    local goal_left = TABLE.x + (TABLE.w - GOAL_W) / 2
    ops[#ops + 1] = { type = "rect", x = goal_left, y = TABLE.y - 3, w = GOAL_W, h = 8,
        radius = 4, color = COLOR.goal }
    ops[#ops + 1] = { type = "rect", x = goal_left, y = TABLE.y + TABLE.h - 5, w = GOAL_W, h = 8,
        radius = 4, color = COLOR.goal }

    for index, dot in ipairs(game.trail) do
        local alpha = index / #game.trail * 0.25
        ops[#ops + 1] = { type = "circle", x = dot.x, y = dot.y, r = PUCK_R * (0.5 + index / #game.trail * 0.4),
            color = string.format("rgba(32,36,43,%.2f)", alpha) }
    end

    ops[#ops + 1] = { type = "circle", x = game.player.x, y = game.player.y, r = PADDLE_R, color = COLOR.player }
    ops[#ops + 1] = { type = "circle", x = game.player.x, y = game.player.y, r = PADDLE_R * 0.55,
        color = COLOR.playerLight }
    ops[#ops + 1] = { type = "circle", x = game.ai.x, y = game.ai.y, r = PADDLE_R, color = COLOR.ai }
    ops[#ops + 1] = { type = "circle", x = game.ai.x, y = game.ai.y, r = PADDLE_R * 0.55,
        color = COLOR.aiLight }

    ops[#ops + 1] = { type = "circle", x = game.puck.x, y = game.puck.y, r = PUCK_R, color = COLOR.puck }
    ops[#ops + 1] = { type = "circle", x = game.puck.x - 2.5, y = game.puck.y - 2.5, r = 2.2,
        color = "rgba(255,255,255,0.35)" }
end

function W.init(w, h, style, id)
    ensure_state()
    math.randomseed(os.time() + #(id or ""))
    new_match(false)
end

function W.render(w, h)
    ensure_state()
    ensure_match()
    W.tick = (game.running and not game.over) and 16 or 0

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "rgba(18,18,21,0.90)", border = 1, borderColor = "rgba(255,255,255,0.10)" },
        { type = "text", x = 18, y = 24, text = "Air Hockey", size = 15, weight = 600,
          color = COLOR.text },
        { type = "text", x = 18, y = 46,
          text = string.format("You %d : %d CPU", game.playerScore, game.aiScore),
          size = 12, color = COLOR.text },
        { type = "text", x = w - 128, y = 46,
          text = "Wins " .. tostring(W.state.wins), size = 10, color = COLOR.wins },
    }

    local nx, ny, nw, nh = slot_new_button()
    ops[#ops + 1] = { type = "rect", x = nx, y = ny, w = nw, h = nh, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = nx + nw / 2, y = ny + nh / 2, text = "New",
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    draw_table(ops)

    if game.over then
        ops[#ops + 1] = { type = "rect", x = TABLE.x, y = TABLE.y, w = TABLE.w, h = TABLE.h,
            radius = 14, color = "rgba(10,14,20,0.66)" }
        local won = game.playerScore > game.aiScore
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 - 20,
            text = won and "You win!" or "CPU wins", size = 26, weight = 700,
            color = won and "#8be28b" or COLOR.ai, align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 + 10,
            text = string.format("%d : %d", game.playerScore, game.aiScore),
            size = 16, color = COLOR.text, align = "center" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 + 34,
            text = "Enter / R for a new match", size = 10, color = COLOR.muted, align = "center" }
    elseif not game.running then
        ops[#ops + 1] = { type = "rect", x = TABLE.x, y = TABLE.y, w = TABLE.w, h = TABLE.h,
            radius = 14, color = "rgba(10,14,20,0.38)" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 - 10,
            text = "Click and move the mouse", size = 15, weight = 600, color = COLOR.text,
            align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 + 14,
            text = "First to " .. WIN_SCORE .. " goals wins", size = 10,
            color = COLOR.muted, align = "center" }
    elseif game.serveTimer > 0 then
        ops[#ops + 1] = { type = "text", x = w / 2, y = TABLE.y + TABLE.h / 2 - 44,
            text = game.message, size = 13, weight = 600, color = COLOR.accent, align = "center" }
    end

    ops[#ops + 1] = { type = "text", x = w / 2, y = h - 8,
        text = "Mouse / arrows move   Space pause   Enter restart",
        size = 9, color = COLOR.muted, align = "center" }

    return ops
end

function W.on_tick(ms)
    ensure_match()
    if lastMs == nil then
        lastMs = ms
    end
    local dt = math.min(0.05, math.max(0, (ms - lastMs) / 1000))
    lastMs = ms
    update(dt)
end

function W.on_hover(x, y)
    ensure_state()
    ensure_match()
    if game.over then
        return
    end
    mouse_active = true
    game.player.x = clamp(x, TABLE.x + PADDLE_R, TABLE.x + TABLE.w - PADDLE_R)
    game.player.y = clamp(y, TABLE.y + TABLE.h / 2 + PADDLE_R, TABLE.y + TABLE.h - PADDLE_R)
    if not game.running then
        game.running = true
        lastMs = nil
    end
end

function W.on_key(key)
    ensure_state()
    ensure_match()
    if key == "enter" or key == "r" then
        new_match(true)
        return
    end
    if key == "space" then
        if game.over then
            new_match(true)
        else
            game.running = not game.running
            lastMs = nil
        end
        return
    end
    held[key] = true
    if not game.running and not game.over then
        game.running = true
        lastMs = nil
    end
end

function W.on_key_release(key)
    held[key] = nil
end

function W.on_blur()
    held = {}
    if game and game.running then
        game.running = false
        lastMs = nil
    end
end

function W.on_click(x, y, button)
    ensure_state()
    ensure_match()

    local nx, ny, nw, nh = slot_new_button()
    if in_rect(x, y, nx, ny, nw, nh) then
        new_match(true)
        return
    end

    if x >= TABLE.x and x <= TABLE.x + TABLE.w and y >= TABLE.y and y <= TABLE.y + TABLE.h then
        if game.over then
            new_match(true)
        else
            game.running = true
            lastMs = nil
        end
    end
end

return W
