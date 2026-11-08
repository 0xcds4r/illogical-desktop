-- Built-in desktop widget: MPRIS media player (card / compact).
--
-- The shell pushes the active player's state into `desktop.media`; controls are
-- sent back with `desktop.media_action(...)`.

local W = { width = 400, height = 160, tick = 0, media = true }
local style = "card"

local COLOR = {
    text = "#eef0f6",
    muted = "#9aa4b8",
    accent = "#8fb4ff",
    onAccent = "#10131a",
    card = "rgba(18,18,21,0.86)",
    edge = "rgba(255,255,255,0.10)",
    art = "rgba(255,255,255,0.06)",
    track = "rgba(255,255,255,0.16)",
}

local PLAY_CARD = { x = 180, y = 130, r = 18 }
local PREV_CARD = { x = 130, y = 118, w = 24, h = 24 }
local NEXT_CARD = { x = 206, y = 118, w = 24, h = 24 }
local BAR_CARD = { x = 134, y = 96, w = 252, h = 4 }

local PLAY_COMPACT = { x = 258, y = 66, r = 16 }
local NEXT_COMPACT = { x = 294, y = 54, w = 22, h = 24 }
local BAR_COMPACT = { x = 86, y = 70, w = 150, h = 4 }

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function fmt(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Cut by UTF-8 code points, not bytes: byte cuts leave a broken glyph in the
-- title (a replacement box) for Cyrillic/Chinese/emoji.
local function utf8_truncate(text, limit)
    local index, count = 1, 0
    while index <= #text do
        local byte = text:byte(index)
        local size = 1
        if byte >= 240 then
            size = 4
        elseif byte >= 224 then
            size = 3
        elseif byte >= 192 then
            size = 2
        end
        count = count + 1
        if count > limit then
            return text:sub(1, index - 1) .. "…"
        end
        index = index + size
    end
    return text
end

local function truncate(text, limit)
    text = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return utf8_truncate(text, limit)
end

local function clean_title(text)
    text = tostring(text or "")
    text = text:gsub("%s*[%(%[]([^%)%]]*)[%)%]]%s*$", "")
    text = text:gsub("%s+$", "")
    if text == "" then
        return "Untitled"
    end
    return text
end

local function in_rect(x, y, r)
    return x >= r.x and x <= r.x + (r.w or (r.r * 2)) and y >= r.y and y <= r.y + (r.h or (r.r * 2))
end

local function in_circle(x, y, c)
    local dx, dy = x - c.x, y - c.y
    return dx * dx + dy * dy <= c.r * c.r
end

local function progress_of(media)
    if (media.length or 0) <= 0 then
        return 0
    end
    return clamp((media.position or 0) / media.length, 0, 1)
end

local function draw_art(ops, media, x, y, size)
    if media.art and media.art ~= "" then
        ops[#ops + 1] = { type = "image", src = media.art, x = x, y = y, w = size, h = size }
    else
        ops[#ops + 1] = { type = "rect", x = x, y = y, w = size, h = size,
            radius = 10, color = COLOR.art }
        ops[#ops + 1] = { type = "text", x = x + size / 2, y = y + size / 2 + 2,
            text = "♫", size = math.floor(size * 0.38), color = COLOR.muted,
            align = "center", valign = "middle" }
    end
    ops[#ops + 1] = { type = "rect", x = x, y = y, w = size, h = size,
        radius = 10, border = 1, borderColor = COLOR.edge }
end

local function draw_button(ops, x, y, size, icon, primary)
    if primary then
        ops[#ops + 1] = { type = "circle", x = x, y = y, r = size / 2, color = COLOR.accent }
    end
    local color = primary and COLOR.onAccent or COLOR.text
    if icon == "play" then
        ops[#ops + 1] = { type = "polygon",
            points = { { x = x - size * 0.18, y = y - size * 0.26 },
                       { x = x + size * 0.28, y = y },
                       { x = x - size * 0.18, y = y + size * 0.26 } },
            color = color }
    elseif icon == "pause" then
        local bar_w, bar_h = size * 0.13, size * 0.44
        ops[#ops + 1] = { type = "rect", x = x - size * 0.20, y = y - bar_h / 2,
            w = bar_w, h = bar_h, radius = 1, color = color }
        ops[#ops + 1] = { type = "rect", x = x + size * 0.06, y = y - bar_h / 2,
            w = bar_w, h = bar_h, radius = 1, color = color }
    elseif icon == "prev" then
        ops[#ops + 1] = { type = "rect", x = x - size * 0.28, y = y - size * 0.26,
            w = 2.5, h = size * 0.52, radius = 1, color = color }
        ops[#ops + 1] = { type = "polygon",
            points = { { x = x + size * 0.26, y = y - size * 0.26 },
                       { x = x - size * 0.14, y = y },
                       { x = x + size * 0.26, y = y + size * 0.26 } },
            color = color }
    elseif icon == "next" then
        ops[#ops + 1] = { type = "rect", x = x + size * 0.24, y = y - size * 0.26,
            w = 2.5, h = size * 0.52, radius = 1, color = color }
        ops[#ops + 1] = { type = "polygon",
            points = { { x = x - size * 0.26, y = y - size * 0.26 },
                       { x = x + size * 0.14, y = y },
                       { x = x - size * 0.26, y = y + size * 0.26 } },
            color = color }
    end
end

local function draw_progress(ops, bar, media, show_times)
    local progress = progress_of(media)
    ops[#ops + 1] = { type = "rect", x = bar.x, y = bar.y, w = bar.w, h = bar.h,
        radius = bar.h / 2, color = COLOR.track }
    if progress > 0 then
        ops[#ops + 1] = { type = "rect", x = bar.x, y = bar.y,
            w = math.max(bar.h, bar.w * progress), h = bar.h,
            radius = bar.h / 2, color = COLOR.accent }
    end
    ops[#ops + 1] = { type = "circle", x = bar.x + bar.w * progress, y = bar.y + bar.h / 2,
        r = 4, color = COLOR.accent }
    if show_times then
        ops[#ops + 1] = { type = "text", x = bar.x, y = bar.y - 8,
            text = fmt(media.position), size = 10, color = COLOR.muted }
        ops[#ops + 1] = { type = "text", x = bar.x + bar.w, y = bar.y - 8,
            text = fmt(media.length), size = 10, color = COLOR.muted, align = "right" }
    end
end

function W.init(w, h, s)
    style = s or "card"
    if style == "compact" then
        W.width, W.height = 320, 104
    else
        W.width, W.height = 400, 160
    end
end

function W.render(w, h)
    local media = desktop.media or {}
    local has_player = media.title ~= nil or media.player ~= nil

    local ops = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 18,
          color = COLOR.card, border = 1, borderColor = COLOR.edge },
    }

    if not has_player then
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 - 12, text = "♫",
            size = 36, color = COLOR.muted, align = "center", valign = "middle" }
        ops[#ops + 1] = { type = "text", x = w / 2, y = h / 2 + 22,
            text = desktop.tr("No active player"), size = 12, color = COLOR.muted,
            align = "center", valign = "middle" }
        return ops
    end

    local playing = media.playing and true or false

    if style == "compact" then
        draw_art(ops, media, 12, 12, 64)
        ops[#ops + 1] = { type = "text", x = 86, y = 32,
            text = truncate(clean_title(media.title), 26), size = 13, weight = 600,
            color = COLOR.text }
        ops[#ops + 1] = { type = "text", x = 86, y = 50,
            text = truncate(media.artist, 28), size = 11, color = COLOR.muted }
        draw_progress(ops, BAR_COMPACT, media, false)
        draw_button(ops, PLAY_COMPACT.x, PLAY_COMPACT.y, 30, playing and "pause" or "play", true)
        draw_button(ops, NEXT_COMPACT.x + 11, NEXT_COMPACT.y + 12, 22, "next", false)
        return ops
    end

    draw_art(ops, media, 14, 14, 104)
    ops[#ops + 1] = { type = "text", x = 134, y = 36,
        text = truncate(clean_title(media.title), 31), size = 15, weight = 600,
        color = COLOR.text }
    ops[#ops + 1] = { type = "text", x = 134, y = 56,
        text = truncate(media.artist, 36), size = 12, color = COLOR.muted }
    draw_progress(ops, BAR_CARD, media, true)
    draw_button(ops, PLAY_CARD.x, PLAY_CARD.y, PLAY_CARD.r * 2, playing and "pause" or "play", true)
    draw_button(ops, PREV_CARD.x + 12, PREV_CARD.y + 12, 24, "prev", false)
    draw_button(ops, NEXT_CARD.x + 12, NEXT_CARD.y + 12, 24, "next", false)
    ops[#ops + 1] = { type = "text", x = 386, y = 136,
        text = playing and desktop.tr("Playing") or desktop.tr("Paused"),
        size = 9, color = COLOR.muted, align = "right" }

    return ops
end

function W.on_click(x, y)
    local media = desktop.media or {}
    if not media.title and not media.player then
        return
    end

    if style == "compact" then
        if in_circle(x, y, PLAY_COMPACT) then
            desktop.media_action("play_pause")
            return
        end
        if in_rect(x, y, NEXT_COMPACT) then
            desktop.media_action("next")
            return
        end
        if x >= BAR_COMPACT.x and x <= BAR_COMPACT.x + BAR_COMPACT.w
            and y >= BAR_COMPACT.y - 8 and y <= BAR_COMPACT.y + 8 + BAR_COMPACT.h then
            if media.canSeek then
                desktop.media_action("seek", clamp((x - BAR_COMPACT.x) / BAR_COMPACT.w, 0, 1))
            end
        end
        return
    end

    if in_circle(x, y, PLAY_CARD) then
        desktop.media_action("play_pause")
        return
    end
    if in_rect(x, y, PREV_CARD) then
        desktop.media_action("previous")
        return
    end
    if in_rect(x, y, NEXT_CARD) then
        desktop.media_action("next")
        return
    end
    if x >= BAR_CARD.x and x <= BAR_CARD.x + BAR_CARD.w
        and y >= BAR_CARD.y - 8 and y <= BAR_CARD.y + 8 + BAR_CARD.h then
        if media.canSeek then
            desktop.media_action("seek", clamp((x - BAR_CARD.x) / BAR_CARD.w, 0, 1))
        end
    end
end

return W
