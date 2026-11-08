-- DesktoCraft — a tiny first-person voxel sandbox widget for illogical-desktop.
--
-- A software 3D renderer written in Lua: blocks are emitted as filled quads,
-- sorted back to front. No textures or game assets are used.
--
-- Controls:
--   W / S                walk forward / back
--   A / D                strafe left / right
--   arrows               look around
--   Space                jump
--   1..6                 select hotbar slot
--   B                    toggle Mine / Build mode
--   left click           mine or place (near the crosshair)
--   middle click         always place
--
-- The seed, player edits, inventory and selected slot persist; the camera and
-- player position are kept in memory.

local W = { width = 480, height = 392, tick = 0 }

local ARENA = { x = 10, y = 66, w = 460, h = 270 }
local WORLD = 48
local HEIGHT = 24
local RENDER_RADIUS = 10
local FOCAL = 176

local GRAVITY = 26
local WALK_SPEED = 4.6
local JUMP_SPEED = 8.4
local LOOK_SPEED = 1.9
local PLAYER_HALF = 0.3
local PLAYER_HEIGHT = 1.8
local EYE_HEIGHT = 1.62
local REACH = 6

local COLOR = {
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    sky = "#86c5e8",
    sun = "#ffe08a",
    button = "rgba(255,255,255,0.07)",
    slot = "rgba(255,255,255,0.05)",
}

local BLOCKS = {
    [1] = { name = "Grass", top = "#5fae37", side = "#7a5230", bottom = "#7a5230" },
    [2] = { name = "Dirt", side = "#7a5230" },
    [3] = { name = "Stone", side = "#8a8a92" },
    [4] = { name = "Wood", side = "#6b4a2b" },
    [5] = { name = "Leaves", side = "#3f8f3a" },
    [6] = { name = "Sand", side = "#d9c37a" },
}
local SLOT_IDS = { 1, 2, 3, 4, 5, 6 }
local MAX_STACK = 999

-- 0 top, 1 bottom, 2 south (+z), 3 north (-z), 4 east (+x), 5 west (-x)
local FACES = {
    { n = { 0, 1, 0 }, off = { 0, 1, 0 }, cx = 0.5, cy = 1, cz = 0.5,
      verts = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 0, 1, 1 } }, shade = 1.0 },
    { n = { 0, -1, 0 }, off = { 0, -1, 0 }, cx = 0.5, cy = 0, cz = 0.5,
      verts = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } }, shade = 0.45 },
    { n = { 0, 0, 1 }, off = { 0, 0, 1 }, cx = 0.5, cy = 0.5, cz = 1,
      verts = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } }, shade = 0.78 },
    { n = { 0, 0, -1 }, off = { 0, 0, -1 }, cx = 0.5, cy = 0.5, cz = 0,
      verts = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 } }, shade = 0.7 },
    { n = { 1, 0, 0 }, off = { 1, 0, 0 }, cx = 1, cy = 0.5, cz = 0.5,
      verts = { { 1, 0, 0 }, { 1, 0, 1 }, { 1, 1, 1 }, { 1, 1, 0 } }, shade = 0.62 },
    { n = { -1, 0, 0 }, off = { -1, 0, 0 }, cx = 0, cy = 0.5, cz = 0.5,
      verts = { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } }, shade = 0.62 },
}

local held = {}
local world = {}
local tops = {}
local generated = false
local rng_state = 0
local mode = "mine"

local player = {
    x = WORLD / 2 + 0.5,
    z = WORLD / 2 + 0.5,
    y = 0,
    vy = 0,
    onGround = true,
    yaw = 0,
    pitch = -0.12,
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function rnd()
    rng_state = (rng_state * 1103515245 + 12345) % 2147483648
    return rng_state / 2147483648
end

local function index(x, y, z)
    return (y * WORLD + z) * WORLD + x + 1
end

local function block(x, y, z)
    if y < 0 then
        return 3
    end
    if x < 0 or x >= WORLD or z < 0 or z >= WORLD or y >= HEIGHT then
        return 0
    end
    return world[index(x, y, z)] or 0
end

local function column_top_slot(x, z)
    return x * WORLD + z + 1
end

local function recompute_top(x, z)
    local slot = column_top_slot(x, z)
    for y = HEIGHT - 1, 0, -1 do
        if (world[index(x, y, z)] or 0) ~= 0 then
            tops[slot] = y + 1
            return
        end
    end
    tops[slot] = 0
end

local function set_block(x, y, z, id)
    if x < 0 or x >= WORLD or z < 0 or z >= WORLD or y < 0 or y >= HEIGHT then
        return false
    end
    world[index(x, y, z)] = id
    W.state.edits[x .. "," .. y .. "," .. z] = id
    local slot = column_top_slot(x, z)
    local top = tops[slot] or 0
    if id ~= 0 then
        if y + 1 > top then
            tops[slot] = y + 1
        end
    elseif y + 1 >= top then
        recompute_top(x, z)
    end
    return true
end

local function shade_color(hex, factor)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    return string.format("#%02x%02x%02x",
        math.floor(r * factor), math.floor(g * factor), math.floor(b * factor))
end

local COLORS = {}
local function build_colors()
    for id, block_def in pairs(BLOCKS) do
        COLORS[id] = {}
        for face = 1, 6 do
            local base
            if face == 1 then
                base = block_def.top or block_def.side
            elseif face == 2 then
                base = block_def.bottom or block_def.side
            else
                base = block_def.side
            end
            COLORS[id][face] = shade_color(base, FACES[face].shade)
        end
    end
end

local function ensure_state()
    if type(W.state) ~= "table" then
        W.state = {}
    end
    W.state.seed = W.state.seed or math.floor(os.time() % 99991)
    W.state.edits = W.state.edits or {}
    W.state.inventory = W.state.inventory or {}
    W.state.selected = W.state.selected or 1
end

local function generate()
    rng_state = W.state.seed
    world = {}
    for x = 0, WORLD - 1 do
        for z = 0, WORLD - 1 do
            local surface = 8 + math.floor(
                1.8 * math.sin(x / 6.5) + 1.6 * math.sin(z / 7.5)
                + 1.2 * math.sin((x + z) / 10) + rnd() * 1.4)
            surface = clamp(surface, 6, HEIGHT - 4)
            for y = 0, HEIGHT - 1 do
                local id = 0
                if y < surface then
                    if y == surface - 1 then
                        id = 1
                    elseif y >= surface - 3 then
                        id = 2
                    else
                        id = 3
                    end
                end
                world[index(x, y, z)] = id
            end
        end
    end

    for x = 3, WORLD - 4, 2 do
        for z = 3, WORLD - 4, 2 do
            local near_spawn = math.abs(x - WORLD / 2) < 3 and math.abs(z - WORLD / 2) < 3
            if not near_spawn and rnd() < 0.035 then
                local surface = 0
                for y = HEIGHT - 1, 0, -1 do
                    if world[index(x, y, z)] ~= 0 then
                        surface = y + 1
                        break
                    end
                end
                local trunk = 3 + math.floor(rnd() * 3)
                for step = 0, trunk - 1 do
                    if surface + step < HEIGHT then
                        world[index(x, surface + step, z)] = 4
                    end
                end
                local top = surface + trunk
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        for dz = -1, 1 do
                            local bx, by, bz = x + dx, top + dy, z + dz
                            if bx >= 0 and bx < WORLD and bz >= 0 and bz < WORLD
                                and by >= 0 and by < HEIGHT
                                and (math.abs(dx) + math.abs(dz) + math.abs(dy)) < 3
                                and world[index(bx, by, bz)] == 0 then
                                world[index(bx, by, bz)] = 5
                            end
                        end
                    end
                end
            end
        end
    end

    for key, id in pairs(W.state.edits) do
        local x, y, z = key:match("(-?%d+),(-?%d+),(-?%d+)")
        if x then
            world[index(tonumber(x), tonumber(y), tonumber(z))] = id
        end
    end

    for x = 0, WORLD - 1 do
        for z = 0, WORLD - 1 do
            recompute_top(x, z)
        end
    end
    generated = true
end

local function spawn_player()
    local x, z = math.floor(WORLD / 2), math.floor(WORLD / 2)
    local surface = 0
    for y = HEIGHT - 1, 0, -1 do
        if block(x, y, z) ~= 0 then
            surface = y + 1
            break
        end
    end
    player.x, player.z = x + 0.5, z + 0.5
    player.y = surface
    player.vy = 0
    player.onGround = true
end

local function box_collides(px, py, pz)
    local min_x, max_x = px - PLAYER_HALF, px + PLAYER_HALF
    local min_z, max_z = pz - PLAYER_HALF, pz + PLAYER_HALF
    local min_y, max_y = py + 0.001, py + PLAYER_HEIGHT - 0.001
    for bx = math.floor(min_x), math.floor(max_x) do
        for by = math.floor(min_y), math.floor(max_y) do
            for bz = math.floor(min_z), math.floor(max_z) do
                if block(bx, by, bz) ~= 0 then
                    return true
                end
            end
        end
    end
    return false
end

local function update_player(dt)
    local look = LOOK_SPEED * dt
    if held.left then player.yaw = player.yaw - look end
    if held.right then player.yaw = player.yaw + look end
    if held.up then player.pitch = clamp(player.pitch + look, -1.35, 1.35) end
    if held.down then player.pitch = clamp(player.pitch - look, -1.35, 1.35) end

    local forward, strafe = 0, 0
    if held.w then forward = forward + 1 end
    if held.s then forward = forward - 1 end
    if held.d then strafe = strafe + 1 end
    if held.a then strafe = strafe - 1 end

    if forward ~= 0 or strafe ~= 0 then
        local sin_yaw, cos_yaw = math.sin(player.yaw), math.cos(player.yaw)
        local dx = sin_yaw * forward + cos_yaw * strafe
        local dz = cos_yaw * forward - sin_yaw * strafe
        local length = math.sqrt(dx * dx + dz * dz)
        if length > 0 then
            dx, dz = dx / length, dz / length
            local step = WALK_SPEED * dt
            if not box_collides(player.x + dx * step, player.y, player.z) then
                player.x = player.x + dx * step
            end
            if not box_collides(player.x, player.y, player.z + dz * step) then
                player.z = player.z + dz * step
            end
        end
    end

    player.vy = player.vy - GRAVITY * dt
    local next_y = player.y + player.vy * dt
    if box_collides(player.x, next_y, player.z) then
        if player.vy < 0 then
            player.onGround = true
            player.y = math.floor(next_y) + 1
        end
        player.vy = 0
    else
        player.y = next_y
        player.onGround = false
    end

    player.x = clamp(player.x, 0.4, WORLD - 0.4)
    player.z = clamp(player.z, 0.4, WORLD - 0.4)
end

local function jump()
    if player.onGround then
        player.vy = JUMP_SPEED
        player.onGround = false
    end
end

local function inventory_count(id)
    return W.state.inventory[id] or 0
end

local function add_item(id, amount)
    W.state.inventory[id] = clamp(inventory_count(id) + amount, 0, MAX_STACK)
end

local function selected_id()
    return SLOT_IDS[W.state.selected] or 1
end

local function forward_vector()
    local cp = math.cos(player.pitch)
    return math.sin(player.yaw) * cp, math.sin(player.pitch), math.cos(player.yaw) * cp
end

local function raycast()
    local ex, ey, ez = player.x, player.y + EYE_HEIGHT, player.z
    local fx, fy, fz = forward_vector()
    local last_x, last_y, last_z
    for step = 1, math.floor(REACH / 0.05) do
        local t = step * 0.05
        local x, y, z = ex + fx * t, ey + fy * t, ez + fz * t
        local bx, by, bz = math.floor(x), math.floor(y), math.floor(z)
        if block(bx, by, bz) ~= 0 then
            return bx, by, bz, last_x, last_y, last_z
        end
        last_x, last_y, last_z = bx, by, bz
    end
    return nil
end

local function overlaps_player(bx, by, bz)
    return bx + 1 > player.x - PLAYER_HALF and bx < player.x + PLAYER_HALF
        and bz + 1 > player.z - PLAYER_HALF and bz < player.z + PLAYER_HALF
        and by + 1 > player.y and by < player.y + PLAYER_HEIGHT
end

local function do_mine()
    local bx, by, bz = raycast()
    if not bx then
        return
    end
    local id = block(bx, by, bz)
    if id == 0 then
        return
    end
    if set_block(bx, by, bz, 0) then
        add_item(id, 1)
    end
end

local function do_place()
    local bx, by, bz, px, py, pz = raycast()
    if not bx then
        return
    end
    local tx, ty, tz = px, py, pz
    if not tx then
        return
    end
    if block(tx, ty, tz) ~= 0 or overlaps_player(tx, ty, tz) then
        return
    end
    local id = selected_id()
    if inventory_count(id) <= 0 then
        return
    end
    if set_block(tx, ty, tz, id) then
        add_item(id, -1)
    end
end

local function project(wx, wy, wz, sin_yaw, cos_yaw, sin_pitch, cos_pitch, ex, ey, ez)
    local dx, dy, dz = wx - ex, wy - ey, wz - ez
    local x1 = dx * cos_yaw - dz * sin_yaw
    local z1 = dx * sin_yaw + dz * cos_yaw
    local y1 = dy
    local y2 = y1 * cos_pitch - z1 * sin_pitch
    local z2 = y1 * sin_pitch + z1 * cos_pitch
    if z2 <= 0.15 then
        return nil
    end
    local inv = FOCAL / z2
    return ARENA.x + ARENA.w / 2 + x1 * inv,
           ARENA.y + ARENA.h / 2 - y2 * inv,
           z2
end

local function render_world(ops)
    ops[#ops + 1] = { type = "rect", x = ARENA.x, y = ARENA.y, w = ARENA.w, h = ARENA.h,
        radius = 4, color = COLOR.sky }
    ops[#ops + 1] = { type = "circle", x = ARENA.x + ARENA.w - 54, y = ARENA.y + 38,
        r = 16, color = COLOR.sun }

    local ex, ey, ez = player.x, player.y + EYE_HEIGHT, player.z
    local sin_yaw, cos_yaw = math.sin(player.yaw), math.cos(player.yaw)
    local sin_pitch, cos_pitch = math.sin(player.pitch), math.cos(player.pitch)
    local faces = {}

    local min_x, max_x = math.floor(player.x) - RENDER_RADIUS, math.floor(player.x) + RENDER_RADIUS
    local min_z, max_z = math.floor(player.z) - RENDER_RADIUS, math.floor(player.z) + RENDER_RADIUS
    local radius_sq = (RENDER_RADIUS + 1) ^ 2
    local forward_x, forward_z = math.sin(player.yaw), math.cos(player.yaw)
    local player_floor = math.floor(player.y)

    for bx = min_x, max_x do
        for bz = min_z, max_z do
            local dx, dz = bx + 0.5 - player.x, bz + 0.5 - player.z
            local distance_sq = dx * dx + dz * dz
            -- Skip columns behind the camera (wide margin keeps the edges filled).
            if distance_sq <= radius_sq
                and dx * forward_x + dz * forward_z >= -0.32 * math.sqrt(distance_sq) then
                local top = tops[column_top_slot(bx, bz)] or 0
                local min_y, max_y
                if player.y >= top - 1 then
                    -- Above ground: no need to walk the enclosed underground.
                    min_y = math.max(0, top - 5)
                    max_y = math.min(HEIGHT - 1, top + 6)
                else
                    min_y = math.max(0, math.min(player_floor - 8, top - 5))
                    max_y = math.min(HEIGHT - 1, math.max(player_floor + 10, top + 6))
                end
                for by = min_y, max_y do
                    local id = world[index(bx, by, bz)]
                    if id and id ~= 0 then
                        for face_index = 1, 6 do
                            local face = FACES[face_index]
                            local nx, ny, nz = face.n[1], face.n[2], face.n[3]
                            local neighbor = block(bx + nx, by + ny, bz + nz)
                            if neighbor == 0 then
                                local cx, cy, cz = bx + face.cx, by + face.cy, bz + face.cz
                                if (ex - cx) * nx + (ey - cy) * ny + (ez - cz) * nz > 0 then
                                    local sx1, sy1, z1 = project(bx + face.verts[1][1], by + face.verts[1][2], bz + face.verts[1][3], sin_yaw, cos_yaw, sin_pitch, cos_pitch, ex, ey, ez)
                                    local sx2, sy2, z2 = project(bx + face.verts[2][1], by + face.verts[2][2], bz + face.verts[2][3], sin_yaw, cos_yaw, sin_pitch, cos_pitch, ex, ey, ez)
                                    local sx3, sy3, z3 = project(bx + face.verts[3][1], by + face.verts[3][2], bz + face.verts[3][3], sin_yaw, cos_yaw, sin_pitch, cos_pitch, ex, ey, ez)
                                    local sx4, sy4, z4 = project(bx + face.verts[4][1], by + face.verts[4][2], bz + face.verts[4][3], sin_yaw, cos_yaw, sin_pitch, cos_pitch, ex, ey, ez)
                                    if sx1 and sx2 and sx3 and sx4 then
                                        -- Expand each quad by half a pixel so adjacent
                                        -- faces overlap and no antialiasing seams show.
                                        local mx = (sx1 + sx2 + sx3 + sx4) / 4
                                        local my = (sy1 + sy2 + sy3 + sy4) / 4
                                        local depth = (z1 + z2 + z3 + z4) / 4
                                        local ex1 = sx1 > mx and sx1 + 0.45 or sx1 - 0.45
                                        local ey1 = sy1 > my and sy1 + 0.45 or sy1 - 0.45
                                        local ex2 = sx2 > mx and sx2 + 0.45 or sx2 - 0.45
                                        local ey2 = sy2 > my and sy2 + 0.45 or sy2 - 0.45
                                        local ex3 = sx3 > mx and sx3 + 0.45 or sx3 - 0.45
                                        local ey3 = sy3 > my and sy3 + 0.45 or sy3 - 0.45
                                        local ex4 = sx4 > mx and sx4 + 0.45 or sx4 - 0.45
                                        local ey4 = sy4 > my and sy4 + 0.45 or sy4 - 0.45
                                        faces[#faces + 1] = {
                                            z = depth,
                                            x1 = math.floor(ex1 + 0.5), y1 = math.floor(ey1 + 0.5),
                                            x2 = math.floor(ex2 + 0.5), y2 = math.floor(ey2 + 0.5),
                                            x3 = math.floor(ex3 + 0.5), y3 = math.floor(ey3 + 0.5),
                                            x4 = math.floor(ex4 + 0.5), y4 = math.floor(ey4 + 0.5),
                                            color = COLORS[id][face_index],
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(faces, function(a, b) return a.z > b.z end)
    for _, face in ipairs(faces) do
        ops[#ops + 1] = {
            type = "quad",
            x1 = face.x1, y1 = face.y1, x2 = face.x2, y2 = face.y2,
            x3 = face.x3, y3 = face.y3, x4 = face.x4, y4 = face.y4,
            color = face.color,
        }
    end
    return #faces
end

local function slot_rect(index)
    local width, gap = 44, 5
    local total = width * #SLOT_IDS + gap * (#SLOT_IDS - 1)
    local x0 = (W.width - total) / 2
    return x0 + (index - 1) * (width + gap), 342, width, 28
end

local function mode_button()
    return W.width - 132, 38, 68, 22
end

local function new_button()
    return W.width - 60, 38, 46, 22
end

local function in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function save_player()
    W.state.player = {
        x = player.x, y = player.y, z = player.z,
        yaw = player.yaw, pitch = player.pitch,
    }
end

local function restore_player()
    local saved = W.state.player
    if type(saved) ~= "table" then
        spawn_player()
        return
    end
    player.x = tonumber(saved.x) or player.x
    player.y = tonumber(saved.y) or player.y
    player.z = tonumber(saved.z) or player.z
    player.yaw = tonumber(saved.yaw) or 0
    player.pitch = tonumber(saved.pitch) or 0
    player.vy = 0
    if box_collides(player.x, player.y, player.z) then
        spawn_player()
    end
end

function W.init(w, h, style, id)
    ensure_state()
    build_colors()
    generate()
    restore_player()
end

function W.render(w, h)
    ensure_state()
    if not generated then
        build_colors()
        generate()
        spawn_player()
    end

    local moving = held.w or held.a or held.s or held.d
        or held.left or held.right or held.up or held.down
        or not player.onGround
    W.tick = moving and 50 or 0

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = "rgba(18,18,21,0.90)", border = 1, borderColor = "rgba(255,255,255,0.10)" },
    }

    render_world(ops)

    ops[#ops + 1] = { type = "text", x = 18, y = 24, text = "DesktoCraft",
        size = 15, weight = 600, color = COLOR.text }
    ops[#ops + 1] = { type = "text", x = 18, y = 46,
        text = string.format("X %.1f  Y %.1f  Z %.1f", player.x, player.y, player.z),
        size = 11, color = COLOR.muted }

    local mode_x, mode_y, mode_w, mode_h = mode_button()
    ops[#ops + 1] = { type = "rect", x = mode_x, y = mode_y, w = mode_w, h = mode_h, radius = 7,
        color = mode == "build" and "rgba(143,180,255,0.28)" or COLOR.button,
        border = 1, borderColor = mode == "build" and COLOR.accent or "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = mode_x + mode_w / 2, y = mode_y + mode_h / 2,
        text = mode == "build" and "Build" or "Mine", size = 11,
        color = mode == "build" and COLOR.accent or COLOR.text, align = "center", valign = "middle" }

    local new_x, new_y, new_w, new_h = new_button()
    ops[#ops + 1] = { type = "rect", x = new_x, y = new_y, w = new_w, h = new_h, radius = 7,
        color = COLOR.button, border = 1, borderColor = "rgba(255,255,255,0.10)" }
    ops[#ops + 1] = { type = "text", x = new_x + new_w / 2, y = new_y + new_h / 2, text = "New",
        size = 11, color = COLOR.text, align = "center", valign = "middle" }

    local cross_x = ARENA.x + ARENA.w / 2
    local cross_y = ARENA.y + ARENA.h / 2
    ops[#ops + 1] = { type = "line", x1 = cross_x - 6, y1 = cross_y, x2 = cross_x - 2, y2 = cross_y,
        width = 1.4, color = "rgba(255,255,255,0.75)" }
    ops[#ops + 1] = { type = "line", x1 = cross_x + 2, y1 = cross_y, x2 = cross_x + 6, y2 = cross_y,
        width = 1.4, color = "rgba(255,255,255,0.75)" }
    ops[#ops + 1] = { type = "line", x1 = cross_x, y1 = cross_y - 6, x2 = cross_x, y2 = cross_y - 2,
        width = 1.4, color = "rgba(255,255,255,0.75)" }
    ops[#ops + 1] = { type = "line", x1 = cross_x, y1 = cross_y + 2, x2 = cross_x, y2 = cross_y + 6,
        width = 1.4, color = "rgba(255,255,255,0.75)" }

    for index, id in ipairs(SLOT_IDS) do
        local sx, sy, sw, sh = slot_rect(index)
        local selected = index == W.state.selected
        ops[#ops + 1] = { type = "rect", x = sx, y = sy, w = sw, h = sh, radius = 6,
            color = selected and "rgba(143,180,255,0.22)" or COLOR.slot,
            border = 1, borderColor = selected and COLOR.accent or "rgba(255,255,255,0.08)" }
        ops[#ops + 1] = { type = "rect", x = sx + 6, y = sy + 6, w = 16, h = 16, radius = 3,
            color = (BLOCKS[id] and BLOCKS[id].side) or "#888888" }
        ops[#ops + 1] = { type = "text", x = sx + 28, y = sy + sh / 2,
            text = tostring(inventory_count(id)), size = 11, color = COLOR.text,
            valign = "middle" }
    end

    ops[#ops + 1] = { type = "text", x = w / 2, y = h - 8,
        text = "WASD move   arrows look   Space jump   1-6 select   B mode   click mine/place",
        size = 9, color = COLOR.muted, align = "center" }

    return ops
end

function W.on_tick()
    update_player(0.04)
end

function W.on_key(key)
    ensure_state()
    if key == "b" then
        mode = mode == "mine" and "build" or "mine"
        return
    end
    local number = tonumber(key)
    if number and number >= 1 and number <= #SLOT_IDS then
        W.state.selected = number
        return
    end
    if key == "space" then
        jump()
        held.space = true
        return
    end
    held[key] = true
end

function W.on_key_release(key)
    held[key] = nil
end

function W.on_blur()
    held = {}
    save_player()
end

function W.on_click(x, y, button)
    ensure_state()

    local mode_x, mode_y, mode_w, mode_h = mode_button()
    if in_rect(x, y, mode_x, mode_y, mode_w, mode_h) then
        mode = mode == "mine" and "build" or "mine"
        return
    end

    local new_x, new_y, new_w, new_h = new_button()
    if in_rect(x, y, new_x, new_y, new_w, new_h) then
        W.state.seed = math.floor(os.time() % 99991)
        W.state.edits = {}
        W.state.inventory = {}
        W.state.selected = 1
        generate()
        spawn_player()
        return
    end

    for index = 1, #SLOT_IDS do
        local sx, sy, sw, sh = slot_rect(index)
        if in_rect(x, y, sx, sy, sw, sh) then
            W.state.selected = index
            return
        end
    end

    if x < ARENA.x or x > ARENA.x + ARENA.w or y < ARENA.y or y > ARENA.y + ARENA.h then
        return
    end

    if button == "middle" then
        do_place()
    elseif mode == "build" then
        do_place()
    else
        do_mine()
    end
    save_player()
end

return W
