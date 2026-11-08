-- illogical-desktop: Lua widget host.
--
-- Usage: lua host.lua <widget.lua> [state-file]
--
-- The QML side sends one command per line over stdin and receives one JSON
-- line per command over stdout:
--
--   i <w> <h> <style>   init / resize
--   t <ms>              animation tick
--   p <x> <y> <button>  press
--   m <x> <y> <buttons> pointer move
--   r <x> <y> <button>  release (calls on_release, then on_click)
--   d <x> <y>           double click
--   w <dy>              wheel
--
-- A widget is a Lua table (returned by the script, or the global `widget`):
--   width, height, tick  - desired size and animation interval in ms (0 = off)
--   render(w, h)         - returns a list of drawing operations
--   init(w, h, style)    - optional, called once
--   on_tick(ms), on_press(x, y, button), on_move(x, y, buttons),
--   on_release(x, y, button), on_click(x, y, button), on_double_click(x, y),
--   on_wheel(dy)         - optional
--   state                - persistent table (saved between restarts)
--
-- Drawing operations (all coordinates in widget-local pixels):
--   { type = "rect",   x, y, w, h, radius, color, border, borderColor }
--   { type = "circle", x, y, r, color, border, borderColor }
--   { type = "line",   x1, y1, x2, y2, width, color }
--   { type = "text",   x, y, text, size, color, align, valign, font }
--   { type = "image",  src, x, y, w, h }
--   { type = "arc",    x, y, r, from, to, width, color }  (radians)

local script_path = arg[1]
local state_path = arg[2] or ""

if not script_path or script_path == "" then
    io.stderr:write("no script path\n")
    os.exit(2)
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

-- State is stored as a Lua literal, so it can hold arbitrary nested tables
-- without pulling a JSON parser into the host.
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
            return "{\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ") .. ",\n" .. indent .. "}"
        end
        for key, item in pairs(value) do
            local key_literal
            if type(key) == "string" then
                key_literal = string.format("[%q]", key)
            else
                key_literal = "[" .. tostring(key) .. "]"
            end
            parts[#parts + 1] = key_literal .. " = " .. serialize(item, indent .. "  ")
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

widget = { width = 320, height = 220, tick = 0, state = state }

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
local current_style = ""

local function save_state()
    if state_path == "" then
        return
    end
    local file = io.open(state_path, "w")
    if not file then
        return
    end
    file:write("return ", serialize(widget.state or {}), "\n")
    file:close()
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
    local payload = {
        ops = render_now(),
        meta = {
            width = widget_width,
            height = widget_height,
            tick = tick_interval
        }
    }
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

if type(widget.init) == "function" then
    pcall(widget.init, widget_width, widget_height, current_style)
end

for line in io.lines() do
    local command, rest = line:match("^(%a)%s*(.*)$")
    if command == "i" then
        local w, h, style = rest:match("([^\t]*)\t([^\t]*)\t?(.*)")
        -- The script's declared size wins; the host size is only a fallback.
        if tonumber(widget.width) == nil then
            widget_width = tonumber(w) or widget_width
        end
        if tonumber(widget.height) == nil then
            widget_height = tonumber(h) or widget_height
        end
        current_style = style or ""
        tick_interval = tonumber(widget.tick) or tick_interval
        call("init", widget_width, widget_height, current_style)
    elseif command == "t" then
        call("on_tick", tonumber(rest) or 0)
    elseif command == "p" or command == "r" then
        local x, y, button = rest:match("([^\t]*)\t([^\t]*)\t?(.*)")
        x, y = tonumber(x) or 0, tonumber(y) or 0
        if command == "p" then
            call("on_press", x, y, button)
        else
            call("on_release", x, y, button)
            call("on_click", x, y, button)
        end
    elseif command == "m" then
        local x, y, buttons = rest:match("([^\t]*)\t([^\t]*)\t?(.*)")
        call("on_move", tonumber(x) or 0, tonumber(y) or 0, buttons)
    elseif command == "d" then
        local x, y = rest:match("([^\t]*)\t([^\t]*)")
        call("on_double_click", tonumber(x) or 0, tonumber(y) or 0)
    elseif command == "w" then
        call("on_wheel", tonumber(rest) or 0)
    elseif command == "x" then
        save_state()
        os.exit(0)
    end
    respond()
end

save_state()
