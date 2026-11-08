-- illogical-desktop: Lua widget host.
--
-- Usage: lua host.lua <widget.lua> [state-file]
--
-- The QML side sends one command per line over stdin and receives one JSON
-- line per command over stdout:
--
--   i <w> <h> <style> <id>     init
--   s <key> <value>            translation entry (percent-encoded)
--   t <ms>                     animation tick
--   p <x> <y> <button> [mods]  press
--   m <x> <y> <buttons> [mods] pointer move (button held)
--   h <x> <y> [mods]           pointer hover
--   n <x> <y>                  pointer entered
--   o                          pointer left
--   r <x> <y> <button> [mods]  release (calls on_release, then on_click)
--   d <x> <y> [button] [mods]  double click
--   w <dy> <dx> [mods]         wheel
--   j <playing> <pos> <len> <seekable> <title> <artist> <album> <art> <player>
--                              media state from the shell (strings percent-encoded)
--   e <key> <text>             text input changed (percent-encoded)
--   k <key> <modifiers>        key pressed
--   u <key> <modifiers>        key released
--   b                          keyboard focus lost
--   x                          close
--
-- A widget is a Lua table (returned by the script, or the global `widget`):
--   width, height, tick, rotation, cursor, context_button
--   render(w, h)               returns a list of drawing operations
--   init(w, h, style, id)
--   on_tick, on_press(x, y, button, mods), on_move(x, y, buttons, mods),
--   on_release(x, y, button, mods), on_click(x, y, button, mods),
--   on_double_click(x, y, button, mods), on_hover(x, y, mods),
--   on_enter(x, y), on_leave(), on_wheel(dy, dx, mods),
--   on_text(key, text), on_key(key, modifiers), on_key_release(key), on_blur
--   state                      persistent table (saved between restarts)
--
-- Drawing operations (widget-local pixels):
--   { type = "rect",   x, y, w, h, radius, color, border, borderColor }
--   { type = "circle", x, y, r, color, border, borderColor }
--   { type = "line",   x1, y1, x2, y2, width, color, lineCap }
--   { type = "text",   x, y, text, size, color, align, valign, font }
--   { type = "image",  src, x, y, w, h }
--   { type = "arc",    x, y, r, from, to, width, color }
--   { type = "input",  key, x, y, w, h, text, size, color, family,
--                      align, multiline, selectionColor, selectedTextColor }
--   { type = "polygon", points = {{x=,y=}, ...}, color, border, borderColor }
--
-- Helpers:
--   desktop.notify(title, body)
--   desktop.spawn(command, arg1, ...)   -- command may also be a table
--   desktop.open(path)
--   desktop.tr(key)
--   desktop.log(...)
--   desktop.strings                     -- translations table
--   desktop.home                        -- $HOME
--   desktop.media                       -- {playing, position, length, canSeek,
--                                          title, artist, album, art, player}
--   desktop.media_action("play_pause" | "next" | "previous" | "seek", value)

local script_path = arg[1]
local state_path = arg[2] or ""

if not script_path or script_path == "" then
    io.stderr:write("no script path\n")
    os.exit(2)
end

local function url_decode(text)
    return (tostring(text):gsub("%%(%x%x)", function(code)
        return string.char(tonumber(code, 16))
    end))
end

local function json_escape(text)
    text = tostring(text)
    text = text:gsub("\\", "\\\\")
    text = text:gsub("\"", "\\\"")
    text = text:gsub("\n", "\\n")
    text = text:gsub("\r", "\\r")
    text = text:gsub("\t", "\\t")
    text = text:gsub("[%z\1-\8\11\12\14-\31]", function(ch)
        return string.format("\\u%04x", string.byte(ch))
    end)
    return text
end

local function is_sequence(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then
            return false, 0
        end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then
            return false, 0
        end
    end
    return true, count
end

local function json_encode(value)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "0"
        end
        return string.format("%.14g", value)
    elseif kind == "string" then
        return "\"" .. json_escape(value) .. "\""
    elseif kind == "table" then
        local sequence, count = is_sequence(value)
        if sequence then
            local parts = {}
            for index = 1, count do
                parts[index] = json_encode(value[index])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = "\"" .. json_escape(key) .. "\":" .. json_encode(item)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function serialize(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "nil" then
        return "nil"
    elseif kind == "boolean" or kind == "number" then
        return tostring(value)
    elseif kind == "string" then
        return string.format("%q", value)
    elseif kind == "table" then
        local sequence, count = is_sequence(value)
        if sequence and count == 0 then
            return "{}"
        end
        local parts = {}
        if sequence then
            for index = 1, count do
                parts[#parts + 1] = serialize(value[index], indent .. "  ")
            end
        else
            for key, item in pairs(value) do
                local key_literal
                if type(key) == "string" then
                    key_literal = string.format("[%q]", key)
                else
                    key_literal = "[" .. tostring(key) .. "]"
                end
                parts[#parts + 1] = key_literal .. " = " .. serialize(item, indent .. "  ")
            end
        end
        return "{\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ") .. ",\n" .. indent .. "}"
    end
    return "nil"
end

local state = {}
if state_path ~= "" then
    local file = io.open(state_path, "r")
    if file then
        local source = file:read("*a")
        file:close()
        local chunk = load(source)
        if chunk then
            local ok, value = pcall(chunk)
            if ok and type(value) == "table" then
                state = value
            end
        end
    end
end

local actions = {}

desktop = {
    home = os.getenv("HOME") or "",
    script_path = script_path,
    dir = script_path:match("^(.*)[/\\][^/\\]*$") or ".",
    strings = {},
}

function desktop.notify(title, body)
    actions[#actions + 1] = { type = "notify", title = tostring(title or ""), body = tostring(body or "") }
end

function desktop.spawn(command, ...)
    local args
    if type(command) == "table" then
        args = command
    else
        args = { command, ... }
    end
    actions[#actions + 1] = { type = "spawn", command = args }
end

function desktop.open(path)
    actions[#actions + 1] = { type = "open", path = tostring(path or "") }
end

function desktop.media_action(command, value)
    actions[#actions + 1] = {
        type = "media",
        command = tostring(command or ""),
        value = tonumber(value) or 0
    }
end

function desktop.tr(key)
    return desktop.strings[tostring(key)] or tostring(key)
end

function desktop.log(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    io.stderr:write(table.concat(parts, "\t"), "\n")
end

-- User scripts must not write to stdout: it carries the protocol. Keep print
-- working by routing it to stderr.
print = function(...)
    desktop.log(...)
end

widget = { width = 320, height = 220, tick = 0, rotation = 0, cursor = "pointing", state = state }

local returned = dofile(script_path)
if type(returned) == "table" then
    widget = returned
end
if type(widget) ~= "table" then
    widget = {}
end
if type(widget.state) ~= "table" then
    widget.state = state
end

local widget_width = tonumber(widget.width) or 320
local widget_height = tonumber(widget.height) or 220
local tick_interval = tonumber(widget.tick) or 0
local widget_rotation = tonumber(widget.rotation) or 0
local widget_cursor = tostring(widget.cursor or "pointing")
local current_style = ""
local current_id = ""

local last_saved = nil

local function save_state()
    if state_path == "" then
        return
    end
    local encoded = "return " .. serialize(widget.state or {}) .. "\n"
    if encoded == last_saved then
        return
    end
    local file = io.open(state_path, "w")
    if not file then
        return
    end
    file:write(encoded)
    file:close()
    last_saved = encoded
end

local function error_ops(message)
    local ops = {
        {
            type = "rect", x = 0, y = 0, w = widget_width, h = widget_height,
            radius = 14, color = "#2a1d1d", border = 1, borderColor = "#7a3d3d"
        }
    }
    local text = "Lua error: " .. tostring(message)
    local line = ""
    local y = 24
    for word in text:gmatch("%S+") do
        if #line > 0 and #line + #word + 1 > 44 then
            ops[#ops + 1] = { type = "text", x = 12, y = y, size = 12, color = "#ffb4b4", text = line }
            y = y + 16
            line = word
        else
            line = (#line == 0) and word or (line .. " " .. word)
        end
    end
    if #line > 0 then
        ops[#ops + 1] = { type = "text", x = 12, y = y, size = 12, color = "#ffb4b4", text = line }
    end
    return ops
end

local function render_now()
    if type(widget.render) ~= "function" then
        return {}
    end
    local ok, ops = pcall(widget.render, widget_width, widget_height)
    if not ok then
        io.stderr:write(tostring(ops), "\n")
        return error_ops(ops)
    end
    if type(ops) ~= "table" then
        return {}
    end
    return ops
end

local function respond()
    -- The script may have changed its declared size/tick in init() or render().
    widget_width = tonumber(widget.width) or widget_width
    widget_height = tonumber(widget.height) or widget_height
    local ops = render_now()
    tick_interval = tonumber(widget.tick) or 0
    widget_rotation = tonumber(widget.rotation) or 0
    widget_cursor = tostring(widget.cursor or "pointing")
    local payload = {
        ops = ops,
        meta = {
            width = tonumber(widget.width) or widget_width,
            height = tonumber(widget.height) or widget_height,
            tick = tick_interval,
            rotation = widget_rotation,
            cursor = widget_cursor,
            context = tostring(widget.context_button or "right"),
            media = widget.media and true or false
        },
        actions = actions
    }
    actions = {}
    io.stdout:write(json_encode(payload), "\n")
    io.stdout:flush()
    save_state()
end

local function call(name, ...)
    if type(widget[name]) == "function" then
        local ok, err = pcall(widget[name], ...)
        if not ok then
            io.stderr:write(tostring(err), "\n")
            return false, err
        end
    end
    return true
end

for line in io.lines() do
    local command, rest = line:match("^(%a)%s*(.*)$")
    local skip_respond = false
    if command == "i" then
        local w, h, style, id = rest:match("([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)")
        if tonumber(widget.width) == nil then
            widget_width = tonumber(w) or widget_width
        end
        if tonumber(widget.height) == nil then
            widget_height = tonumber(h) or widget_height
        end
        current_style = style or ""
        current_id = id or ""
        call("init", widget_width, widget_height, current_style, current_id)
    elseif command == "s" then
        local key, value = rest:match("([^\t]*)\t?(.*)")
        if key and key ~= "" then
            desktop.strings[url_decode(key)] = url_decode(value or "")
        end
        -- Translation entries do not trigger a repaint.
        skip_respond = true
    elseif command == "t" then
        call("on_tick", tonumber(rest) or 0)
    elseif command == "p" or command == "r" then
        local x, y, button, mods = rest:match("([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)")
        x, y = tonumber(x) or 0, tonumber(y) or 0
        if command == "p" then
            call("on_press", x, y, button or "", mods or "")
        else
            call("on_release", x, y, button or "", mods or "")
            call("on_click", x, y, button or "", mods or "")
        end
    elseif command == "m" then
        local x, y, buttons, mods = rest:match("([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)")
        call("on_move", tonumber(x) or 0, tonumber(y) or 0, buttons or "", mods or "")
    elseif command == "h" then
        local x, y, mods = rest:match("([^\t]*)\t([^\t]*)\t?(.*)")
        call("on_hover", tonumber(x) or 0, tonumber(y) or 0, mods or "")
    elseif command == "n" then
        local x, y = rest:match("([^\t]*)\t([^\t]*)")
        call("on_enter", tonumber(x) or 0, tonumber(y) or 0)
    elseif command == "o" then
        call("on_leave")
    elseif command == "d" then
        local x, y, button, mods = rest:match("([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)")
        call("on_double_click", tonumber(x) or 0, tonumber(y) or 0, button or "", mods or "")
    elseif command == "w" then
        local dy, dx, mods = rest:match("([^\t]*)\t?([^\t]*)\t?(.*)")
        call("on_wheel", tonumber(dy) or 0, tonumber(dx) or 0, mods or "")
    elseif command == "j" then
        local fields = {}
        for part in (rest .. "\t"):gmatch("([^\t]*)\t") do
            fields[#fields + 1] = part
        end
        desktop.media = {
            playing = fields[1] == "1",
            position = tonumber(fields[2]) or 0,
            length = tonumber(fields[3]) or 0,
            canSeek = fields[4] == "1",
            title = url_decode(fields[5] or ""),
            artist = url_decode(fields[6] or ""),
            album = url_decode(fields[7] or ""),
            art = url_decode(fields[8] or ""),
            player = url_decode(fields[9] or "")
        }
        call("on_media", desktop.media)
    elseif command == "e" then
        local key, text = rest:match("([^\t]*)\t?(.*)")
        if key and key ~= "" then
            call("on_text", key, url_decode(text or ""))
        end
    elseif command == "k" or command == "u" then
        local key, mods = rest:match("([^\t]*)\t?(.*)")
        if command == "k" then
            call("on_key", key or "", mods or "")
        else
            call("on_key_release", key or "", mods or "")
        end
    elseif command == "b" then
        call("on_blur")
    elseif command == "x" then
        save_state()
        os.exit(0)
    end
    if not skip_respond then
        respond()
    end
end

save_state()
