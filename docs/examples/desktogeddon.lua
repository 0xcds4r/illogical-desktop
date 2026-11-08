-- DesktoGeddon — a top-down vehicular mayhem widget for illogical-desktop.
--
-- Drive around the arena and run over pedestrians before the clock runs out.
--
-- Controls:
--   W / up, S / down       accelerate / brake + reverse
--   A / left, D / right    steer
--   Space                  pause / resume
--   Enter / R              new round
--   (or click the arena to start, and the New button)
--
-- Best score is persistent. The live round is kept in memory so the widget does
-- not rewrite its state file on every frame.

local W = { width = 400, height = 336, tick = 0 }

local ARENA = { x = 12, y = 66, w = 376, h = 240 }
local ROUND_TIME = 60
local PED_COUNT = 8

local MAX_SPEED = 200
local ACCEL = 330
local DRAG = 1.45
local TURN = 3.1

local COLOR = {
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    asphalt = "#1b1c21",
    line = "rgba(255,255,255,0.06)",
    car = "#c0392b",
    carDark = "#7e2318",
    glass = "#1d2b3a",
    wheel = "#0d0d10",
    skin = "#e8c39e",
    blood = "#8f1d1d",
    popup = "#ffd166",
    button = "rgba(255,255,255,0.07)",
}

local atan2 = math.atan2 or math.atan

-- Optional local art pack (never shipped with the add-on):
-- <script dir>/desktogeddon-assets/{asphalt,car,ped,blood}.png
-- Sprite conventions: car faces right, pedestrian faces up, blood is a splat.
local ASSET_DIR = ((desktop and desktop.dir) or ".") .. "/desktogeddon-assets"

local function asset_file(name)
    local path = ASSET_DIR .. "/" .. name
    local file = io.open(path, "rb")
    if file then
        file:close()
        return "file://" .. path
    end
    return nil
end

local ASSETS = {
    asphalt = asset_file("asphalt.png"),
    car = asset_file("car.png"),
    ped = asset_file("ped.png"),
    blood = asset_file("blood.png"),
}

local held = {}
local game
local lastMs = nil
local best = 0

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function random_point(margin)
    return {
        x = ARENA.x + margin + math.random() * (ARENA.w - margin * 2),
        y = ARENA.y + margin + math.random() * (ARENA.h - margin * 2),
    }
end

local function make_ped()
    local point = random_point(18)
    return {
        x = point.x,
        y = point.y,
        angle = math.random() * math.pi * 2,
        speed = 16 + math.random() * 14,
        phase = math.random() * math.pi * 2,
        wander = 0,
    }
end

local function new_round()
    local car = { x = ARENA.x + ARENA.w / 2, y = ARENA.y + ARENA.h / 2, angle = 0, speed = 0 }
    local peds = {}
    for _ = 1, PED_COUNT do
        peds[#peds + 1] = make_ped()
    end
    -- Put one pedestrian right in front of the car so there is an easy first kill.
    peds[1].x = math.min(ARENA.x + ARENA.w - 20, car.x + 70)
    peds[1].y = car.y
    game = {
        car = car,
        peds = peds,
        splats = {},
        particles = {},
        popups = {},
        score = 0,
        timeLeft = ROUND_TIME,
        running = false,
        started = false,
        over = false,
    }
    lastMs = nil
end

local function ensure_round()
    if type(W.state) ~= "table" then
        W.state = {}
    end
    best = tonumber(W.state.best) or 0
    if not game then
        new_round()
    end
end

local function rotated_point(cx, cy, angle, px, py)
    local c, s = math.cos(angle), math.sin(angle)
    return cx + px * c - py * s, cy + px * s + py * c
end

local function car_polygon(car, half_length, half_width)
    local points = {}
    for _, corner in ipairs({
        { -half_length, -half_width },
        { half_length, -half_width },
        { half_length, half_width },
        { -half_length, half_width },
    }) do
        local x, y = rotated_point(car.x, car.y, car.angle, corner[1], corner[2])
        points[#points + 1] = { x = x, y = y }
    end
    return points
end

local function splat(x, y)
    game.splats[#game.splats + 1] = {
        x = x + (math.random() - 0.5) * 10,
        y = y + (math.random() - 0.5) * 10,
        r = 4 + math.random() * 6,
        angle = math.random() * math.pi * 2,
        alpha = 0.55 + math.random() * 0.35,
    }
    if #game.splats > 40 then
        table.remove(game.splats, 1)
    end
end

local function burst(x, y)
    for _ = 1, 10 do
        local angle = math.random() * math.pi * 2
        local speed = 30 + math.random() * 90
        game.particles[#game.particles + 1] = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.35 + math.random() * 0.35,
            maxLife = 0.7,
            r = 1 + math.random() * 1.8,
        }
    end
end

local function hit_ped(index)
    local ped = game.peds[index]
    splat(ped.x, ped.y)
    burst(ped.x, ped.y)
    game.popups[#game.popups + 1] = { x = ped.x, y = ped.y, text = "+100", life = 0.9 }
    game.score = game.score + 100
    table.remove(game.peds, index)

    -- Respawn away from the car so the arena does not empty out.
    local replacement
    repeat
        replacement = make_ped()
    until math.abs(replacement.x - game.car.x) + math.abs(replacement.y - game.car.y) > 120
    game.peds[#game.peds + 1] = replacement
end

local function update_peds(dt)
    for index = #game.peds, 1, -1 do
        local ped = game.peds[index]
        local dx, dy = ped.x - game.car.x, ped.y - game.car.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance < 72 then
            ped.angle = atan2(dy, dx) + (math.random() - 0.5) * 0.25
            ped.speed = 48
        else
            ped.wander = ped.wander - dt
            if ped.wander <= 0 then
                ped.wander = 0.8 + math.random() * 1.8
                ped.angle = ped.angle + (math.random() - 0.5) * 2.4
            end
            ped.speed = 18
        end

        ped.x = ped.x + math.cos(ped.angle) * ped.speed * dt
        ped.y = ped.y + math.sin(ped.angle) * ped.speed * dt
        ped.phase = ped.phase + dt * (distance < 96 and 16 or 6)

        if ped.x < ARENA.x + 8 then
            ped.x = ARENA.x + 8
            ped.angle = math.pi - ped.angle
        elseif ped.x > ARENA.x + ARENA.w - 8 then
            ped.x = ARENA.x + ARENA.w - 8
            ped.angle = math.pi - ped.angle
        end
        if ped.y < ARENA.y + 8 then
            ped.y = ARENA.y + 8
            ped.angle = -ped.angle
        elseif ped.y > ARENA.y + ARENA.h - 8 then
            ped.y = ARENA.y + ARENA.h - 8
            ped.angle = -ped.angle
        end

        if distance < 13 then
            hit_ped(index)
        end
    end
end

local function update_car(dt)
    local car = game.car
    local throttle = 0
    if held.w or held.up then
        throttle = throttle + 1
    end
    if held.s or held.down then
        throttle = throttle - 1
    end
    local steer = 0
    if held.a or held.left then
        steer = steer + 1
    end
    if held.d or held.right then
        steer = steer - 1
    end

    car.speed = car.speed + throttle * ACCEL * dt
    car.speed = car.speed * (1 - DRAG * dt)
    car.speed = clamp(car.speed, -MAX_SPEED * 0.45, MAX_SPEED)

    if steer ~= 0 and math.abs(car.speed) > 5 then
        local grip = clamp(math.abs(car.speed) / 90 + 0.2, 0.2, 1)
        car.angle = car.angle + steer * TURN * dt * grip * (car.speed >= 0 and 1 or -1)
    end

    car.x = car.x + math.cos(car.angle) * car.speed * dt
    car.y = car.y + math.sin(car.angle) * car.speed * dt

    local minX, maxX = ARENA.x + 12, ARENA.x + ARENA.w - 12
    local minY, maxY = ARENA.y + 12, ARENA.y + ARENA.h - 12
    if car.x < minX then
        car.x = minX
        car.speed = -car.speed * 0.3
    elseif car.x > maxX then
        car.x = maxX
        car.speed = -car.speed * 0.3
    end
    if car.y < minY then
        car.y = minY
        car.speed = -car.speed * 0.3
    elseif car.y > maxY then
        car.y = maxY
        car.speed = -car.speed * 0.3
    end
end

local function update_effects(dt)
    for index = #game.particles, 1, -1 do
        local particle = game.particles[index]
        particle.x = particle.x + particle.vx * dt
        particle.y = particle.y + particle.vy * dt
        particle.vx = particle.vx * (1 - 2.4 * dt)
        particle.vy = particle.vy * (1 - 2.4 * dt)
        particle.life = particle.life - dt
        if particle.life <= 0 then
            table.remove(game.particles, index)
        end
    end
    for index = #game.popups, 1, -1 do
        local popup = game.popups[index]
        popup.y = popup.y - 24 * dt
        popup.life = popup.life - dt
        if popup.life <= 0 then
            table.remove(game.popups, index)
        end
    end
end

local function update(dt)
    if not game or not game.running or game.over then
        return
    end
    game.timeLeft = game.timeLeft - dt
    if game.timeLeft <= 0 then
        game.timeLeft = 0
        game.over = true
        game.running = false
        best = math.max(best, game.score)
        W.state.best = best
        return
    end
    update_car(dt)
    update_peds(dt)
    update_effects(dt)
end

local function start_round()
    if game.over then
        new_round()
    end
    game.running = true
    game.started = true
    lastMs = nil
end

local function draw_arena(ops, w, h)
    if ASSETS.asphalt then
        ops[#ops + 1] = { type = "image", src = ASSETS.asphalt,
            x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h }
        ops[#ops + 1] = { type = "rect", x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h,
            radius = 8, border = 1, borderColor = "rgba(255,255,255,0.08)" }
        return
    end

    ops[#ops + 1] = { type = "rect", x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h,
        radius = 8, color = COLOR.asphalt, border = 1, borderColor = "rgba(255,255,255,0.08)" }

    for offset = 1, 3 do
        local y = ARENA.y + ARENA.h * offset / 4
        for x = ARENA.x + 24, ARENA.x + ARENA.w - 24, 44 do
            ops[#ops + 1] = { type = "line", x1 = x, y1 = y, x2 = x + 22, y2 = y,
                width = 1.5, color = COLOR.line }
        end
    end
end

local function draw_ped(ops, ped)
    if ASSETS.ped then
        ops[#ops + 1] = { type = "image", src = ASSETS.ped,
            x = ped.x - 6, y = ped.y - 8, w = 12, h = 16,
            angle = ped.angle + math.pi / 2 }
        return
    end
    local swing = math.sin(ped.phase) * 4
    ops[#ops + 1] = { type = "line", x1 = ped.x, y1 = ped.y,
        x2 = ped.x - 5, y2 = ped.y + swing, width = 1.6, color = COLOR.skin }
    ops[#ops + 1] = { type = "line", x1 = ped.x, y1 = ped.y,
        x2 = ped.x + 5, y2 = ped.y - swing, width = 1.6, color = COLOR.skin }
    ops[#ops + 1] = { type = "circle", x = ped.x, y = ped.y, r = 3.6, color = "#d9d9d9" }
    ops[#ops + 1] = { type = "circle", x = ped.x, y = ped.y - 5.5, r = 2.4, color = COLOR.skin }
end

local function draw_car(ops, car)
    if ASSETS.car then
        ops[#ops + 1] = { type = "image", src = ASSETS.car,
            x = car.x - 19, y = car.y - 12, w = 38, h = 24, angle = car.angle }
        return
    end
    local body = car_polygon(car, 13, 7)
    ops[#ops + 1] = { type = "polygon", points = body, color = COLOR.car,
        border = 1, borderColor = COLOR.carDark }

    local glass = car_polygon({ x = car.x, y = car.y, angle = car.angle }, 4.5, 5)
    -- shift the glass forward along the heading
    local fx, fy = math.cos(car.angle) * 3, math.sin(car.angle) * 3
    for _, point in ipairs(glass) do
        point.x = point.x + fx
        point.y = point.y + fy
    end
    ops[#ops + 1] = { type = "polygon", points = glass, color = COLOR.glass }

    for _, wheel in ipairs({ { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } }) do
        local wx, wy = rotated_point(car.x, car.y, car.angle, wheel[1], wheel[2])
        ops[#ops + 1] = { type = "circle", x = wx, y = wy, r = 2.6, color = COLOR.wheel }
    end

    local hx1, hy1 = rotated_point(car.x, car.y, car.angle, 12, -4)
    local hx2, hy2 = rotated_point(car.x, car.y, car.angle, 12, 4)
    ops[#ops + 1] = { type = "circle", x = hx1, y = hy1, r = 1.4, color = "#ffe9a8" }
    ops[#ops + 1] = { type = "circle", x = hx2, y = hy2, r = 1.4, color = "#ffe9a8" }
end

function W.init(w, h, style, id)
    math.randomseed(os.time() + #(id or ""))
    ensure_round()
end

function W.render(w, h)
    ensure_round()
    W.tick = (game.running and not game.over) and 33 or 0

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "rgba(18,18,21,0.86)", border = 1, borderColor = "rgba(255,255,255,0.10)" },
        { type = "text", x = 16, y = 24, text = "DesktoGeddon", size = 15, weight = 600,
          color = COLOR.text },
        { type = "text", x = 16, y = 46,
          text = string.format("Score %d   Best %d   %02d s", game.score, best, math.ceil(game.timeLeft)),
          size = 11, color = COLOR.muted },
    }

    local new = { x = w - 58, y = 38, w = 46, h = 22 }
    ops[#ops + 1] = { type = "rect", x = new.x, y = new.y, w = new.w, h = new.h, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = new.x + new.w / 2, y = new.y + new.h / 2, text = "New",
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    draw_arena(ops, w, h)

    for _, blob in ipairs(game.splats) do
        if ASSETS.blood then
            local size = blob.r * 2.4
            ops[#ops + 1] = { type = "image", src = ASSETS.blood,
                x = blob.x - size / 2, y = blob.y - size / 2, w = size, h = size,
                angle = blob.angle }
        else
            ops[#ops + 1] = { type = "circle", x = blob.x, y = blob.y, r = blob.r,
                color = string.format("rgba(143,29,29,%.2f)", blob.alpha) }
        end
    end

    for _, ped in ipairs(game.peds) do
        draw_ped(ops, ped)
    end
    draw_car(ops, game.car)

    for _, particle in ipairs(game.particles) do
        local alpha = math.max(0, math.min(1, particle.life / particle.maxLife))
        ops[#ops + 1] = { type = "circle", x = particle.x, y = particle.y, r = particle.r,
            color = string.format("rgba(190,40,40,%.2f)", alpha) }
    end

    for _, popup in ipairs(game.popups) do
        ops[#ops + 1] = { type = "text", x = popup.x, y = popup.y, text = popup.text,
            size = 13, weight = 700, color = COLOR.popup, align = "center" }
    end

    if game.over then
        ops[#ops + 1] = { type = "rect", x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h,
            radius = 8, color = "rgba(10,10,14,0.70)" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = ARENA.y + ARENA.h / 2 - 18,
            text = "TIME'S UP", size = 26, weight = 700, color = COLOR.popup,
            align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = ARENA.y + ARENA.h / 2 + 10,
            text = "Score " .. game.score .. "   Best " .. best,
            size = 13, color = COLOR.text, align = "center" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = ARENA.y + ARENA.h / 2 + 32,
            text = "Press Enter / R for a new round", size = 10, color = COLOR.muted,
            align = "center" }
    elseif not game.running then
        ops[#ops + 1] = { type = "rect", x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h,
            radius = 8, color = "rgba(10,10,14,0.45)" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = ARENA.y + ARENA.h / 2 - 10,
            text = game.started and "Paused" or "Press W / Arrow to start",
            size = 15, weight = 600, color = COLOR.text,
            align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = ARENA.y + ARENA.h / 2 + 14,
            text = game.started and "Press Space to resume"
                or "Run over pedestrians before the timer ends",
            size = 10, color = COLOR.muted, align = "center" }
    end

    ops[#ops + 1] = { type = "text", x = w / 2, y = h - 10,
        text = "WASD / arrows drive   Space pause   Enter restart",
        size = 9, color = COLOR.muted, align = "center" }

    return ops
end

function W.on_tick(ms)
    ensure_round()
    if lastMs == nil then
        lastMs = ms
    end
    local dt = math.min(0.08, math.max(0, (ms - lastMs) / 1000))
    lastMs = ms
    update(dt)
end

function W.on_key(key, modifiers)
    ensure_round()
    if key == "enter" or key == "r" then
        new_round()
        start_round()
        return
    end
    if key == "space" then
        if game.over then
            new_round()
            start_round()
        else
            game.running = not game.running
            lastMs = nil
        end
        return
    end
    held[key] = true
    if not game.running and not game.over then
        start_round()
    end
end

function W.on_key_release(key)
    held[key] = nil
end

function W.on_blur()
    if game and game.running then
        game.running = false
        lastMs = nil
    end
end

function W.on_click(x, y)
    ensure_round()
    local newX, newY, newW, newH = W.width - 58, 38, 46, 22
    if x >= newX and x <= newX + newW and y >= newY and y <= newY + newH then
        new_round()
        start_round()
        return
    end
    if x >= ARENA.x and x <= ARENA.x + ARENA.w and y >= ARENA.y and y <= ARENA.y + ARENA.h then
        if game.over then
            new_round()
        end
        start_round()
    end
end

return W
