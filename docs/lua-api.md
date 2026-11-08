# Lua widget API

Custom desktop widgets are plain Lua scripts. Each widget instance runs in its own
`lua` process and draws through a small immediate-mode API: the script returns a list
of drawing operations, the add-on renders them, and mouse/text events are sent back to
the script.

Bundled widgets (`clock`, `calendar`, `datetime`, `notes`, `timer`, `paint`) are written
with this same API and live in `modules/ii/background/desktop/lua/widgets/`. Copy one of
them as a starting point.

## Requirements

- `lua` in `PATH`. Lua 5.1+ works; the add-on is tested with 5.4/5.5.
- No extra Lua modules are needed — the host provides everything below.

## Where scripts live

```
<desktop folder>/.widgets/*.lua
```

By default `~/Desktop/.widgets/`; the folder follows the “Desktop folder” setting. It is
hidden from the icon grid. Add a widget from **Settings → Widgets → Custom widgets**, or
add `custom` records manually. The **Create example** button drops a commented example
into the folder; **Open folder** opens it.

Editing a script does not reload it automatically: right-click the widget →
**Reload script**. Duplicating a widget copies its script reference and its saved state.

## Execution model

For every widget instance the add-on starts:

```
lua <module>/lua/host.lua <script.lua> <state-file>
```

and talks to it over stdin/stdout. You do not implement the protocol; the host calls your
callbacks.

```
init  →  render  →  tick / input events  →  render  →  …
```

`render` is called again after every event and every tick, so it should be cheap and
should only build the operation list. Put mutation in the callbacks.

The process is restarted when the widget is reloaded or when the declared size changes.

## The widget table

A script returns a table (or assigns the global `widget`):

```lua
local W = {
    width = 300,          -- preferred width in px
    height = 180,         -- preferred height in px
    tick = 50,            -- render interval in ms; 0 disables the timer
    rotation = 0,         -- whole-widget rotation in degrees
    cursor = "pointing",  -- "pointing" | "arrow" | "cross" | "text" | "hand"
}

function W.init(w, h, style, id) ... end
function W.render(w, h) ... end
function W.on_click(x, y, button) ... end

return W
```

| field | meaning |
|---|---|
| `width`, `height` | Preferred size. The add-on resizes the card to match (and remembers it). |
| `tick` | Repaint/animation interval in ms. Evaluated after every render, so it can change at runtime (the timer widget switches between 0 and 250). |
| `rotation` | Rotates the whole widget. The canvas clips at the widget bounds, so inset the content if you tilt it (see `notes.lua`). |
| `cursor` | Mouse cursor over the widget. |
| `state` | Persistent table, filled by the host (see below). |

## Callbacks

| callback | when |
|---|---|
| `init(w, h, style, id)` | Process start / resize. `style` and `id` come from the widget record. |
| `render(w, h)` | Must return the list of drawing operations. |
| `on_tick(ms)` | Every `tick` ms; `ms` is `Date.now()`. |
| `on_press(x, y, button)` | Left/middle button pressed. |
| `on_move(x, y, buttons)` | Pointer moved while pressed (`buttons` is `"left"` or `"other"`). |
| `on_release(x, y, button)` | Button released (before `on_click`). |
| `on_click(x, y, button)` | After a release, including drags. |
| `on_double_click(x, y)` | Double click. |
| `on_wheel(dy)` | Wheel/touchpad scroll; `dy` is `angleDelta.y` (usually ±120). |
| `on_text(key, text)` | An `input` editor changed or lost focus. `key` is the op’s `key`. |

`button` is `"left"` or `"middle"`. The right button is reserved for the widget context
menu (Duplicate / Reload / Remove) and never reaches the script.

Callbacks run protected: an error is logged to stderr and the widget keeps running.

## Drawing operations

`render` returns an array of tables, painted in order. All coordinates are local to the
widget (0,0 is its top-left corner). Colours are CSS strings, including alpha:
`"#82aaff"`, `"rgba(18,18,21,0.74)"`.

### `rect`

```lua
{ type = "rect", x = 0, y = 0, w = 300, h = 130,
  radius = 18, color = "#12141a", border = 1, borderColor = "#2b3140" }
```

Fill is skipped when `color` is `nil`; border is skipped when `border` is 0/nil.

### `circle`

```lua
{ type = "circle", x = 150, y = 80, r = 30, color = "#82aaff",
  border = 2, borderColor = "#ffffff" }
```

### `line`

```lua
{ type = "line", x1 = 10, y1 = 10, x2 = 120, y2 = 40,
  width = 3, color = "#ffffff", lineCap = "round" }
```

### `arc`

```lua
{ type = "arc", x = 150, y = 150, r = 116,
  from = -math.pi / 2, to = math.pi, width = 8, color = "#82aaff" }
```

Angles are radians; the stroke is open (no fill).

### `text`

```lua
{ type = "text", x = 150, y = 80, text = "Hello", size = 18,
  color = "#ffffff", align = "center", valign = "middle",
  font = "sans-serif", weight = 600 }
```

| field | default | notes |
|---|---|---|
| `text` | `""` | `\n` starts a new line |
| `size` | 14 | pixels |
| `align` | `"left"` | `"left"`, `"center"`, `"right"` |
| `valign` | alphabetic baseline | `"middle"` centres on `y` |
| `font` | `"sans-serif"` | any installed family |
| `weight` | normal | e.g. `600`, `"bold"` |

### `image`

```lua
{ type = "image", src = "file:///home/me/picture.png", x = 8, y = 40, w = 120, h = 90 }

-- rotated sprite (angle in radians, around the image centre)
{ type = "image", src = "file:///home/me/car.png", x = x - 19, y = y - 12,
  w = 38, h = 24, angle = heading }
```

Loaded asynchronously; the widget repaints when the image becomes ready. Transparent
PNGs work. Use an absolute `file://` URL.

### `polygon`

```lua
{ type = "polygon",
  points = { { x = 20, y = 10 }, { x = 60, y = 10 }, { x = 40, y = 40 } },
  color = "#c0392b", border = 1, borderColor = "#7e2318" }
```

Closed path, filled when `color` is set, stroked when `border > 0`. Handy for cars,
arrows, flags and other rotated shapes.

### `quad`

```lua
{ type = "quad", x1 = 10, y1 = 10, x2 = 80, y2 = 14,
  x3 = 76, y3 = 60, x4 = 6, y4 = 56, color = "#8a8a92" }
```

A filled four-point polygon. Use it for software-rendered 3D: it has the smallest JSON
footprint and skips path/stroke handling.

### `input`

Places a native text editor inside the widget. This is how the notes widget edits text.

```lua
{ type = "input", key = "note", x = 16, y = 44, w = 228, h = 160,
  text = W.state.text or "", size = 12, color = "#2b2b2b",
  family = "sans-serif", multiline = true,
  selectionColor = "#8a7a3a", selectedTextColor = "#ffffff" }
```

| field | default | notes |
|---|---|---|
| `key` | `"default"` | echoed back in `on_text(key, text)` |
| `text` | `""` | updated only while the editor is not focused, so typing is never interrupted |
| `multiline` | `true` | `false` gives a single-line `TextInput` |
| `align` | left | only `"center"` is treated specially |
| `hidden` | `false` | keeps the editor but hides it |

Changes are reported on every edit and again when the editor loses focus. Keep the text
in `W.state` inside `on_text`.

## Mouse

All coordinates are local to the widget; they can go negative while dragging outside it.
Button names are `"left"` and `"middle"`; `mods` is a `+` set such as `"ctrl+shift"`
(possible: `ctrl`, `alt`, `shift`, `meta`).

```lua
function W.on_hover(x, y, mods)      -- no button held
    paddle.x = clamp(x, arena.x, arena.x + arena.w)
end

function W.on_move(x, y, buttons, mods)  -- while dragging
    -- buttons: "left", "middle", "left+middle"
end

function W.on_wheel(dy, dx, mods)
    zoom = clamp(zoom + dy / 120, 0.5, 4)
end

function W.on_enter(x, y) ... end
function W.on_leave() ... end
```

`on_press` / `on_release` / `on_click` / `on_double_click` also receive the button and
modifier string. Clicks are still needed to give the widget keyboard focus; hover works
without focus.

The **right button is reserved** for the widget context menu (Duplicate / Reload /
Remove) by default, so scripts receive only left and middle button events. A widget can
move the menu to another button:

```lua
local W = {
    width = 320, height = 240,
    context_button = "middle",   -- a mouse button: "right" (default) | "middle" | "none"
    -- context_button = "f1",    -- or any key ...
    -- context_button = "ctrl+m" -- ... with modifiers
}
```

- `"right"` (default) — menu on the right mouse button, the script gets left + middle.
- `"middle"` — menu on the middle button, the script gets **right** instead.
- `"none"` — no context menu; the script gets middle and right.
- A key name (`"f1"`, `"m"`, `"space"`, ...) or a combination (`"ctrl+m"`,
  `"shift+f2"`): the menu opens when that key is pressed **while the widget has keyboard
  focus** (click it once). All mouse buttons then go to the script.

The top 34 px drag strip still belongs to the window manager, and a middle/right press
there drags the card (a plain click opens the menu when it is mapped to that button).

## Keyboard

Clicking a widget gives it keyboard focus; key presses then go to its script until you
click somewhere else (the desktop or another widget). Losing focus calls `on_blur()`,
which is handy to pause a game.

```lua
local DIRECTIONS = {
    left = "left", right = "right", up = "up", down = "down",
    a = "left", d = "right", w = "up", s = "down",
}

function W.on_key(key, modifiers)
    local direction = DIRECTIONS[key]
    if direction then
        steer(direction)
    elseif key == "space" then
        toggle_pause()
    elseif key == "enter" then
        restart()
    end
end

function W.on_blur()
    pause()
end
```

Key names:

| keys | `key` value |
|---|---|
| arrows | `"left"`, `"right"`, `"up"`, `"down"` |
| letters / digits | the character, lower-case (`"a"`, `"7"`) |
| space, enter, escape, tab, backspace, delete | `"space"`, `"enter"`, `"escape"`, `"tab"`, `"backspace"`, `"delete"` |
| home, end, page up/down | `"home"`, `"end"`, `"pageup"`, `"pagedown"` |
| anything else | `"key_<Qt key code>"` |

`modifiers` is a `+`-joined set such as `"ctrl+shift"` (possible: `ctrl`, `alt`, `shift`,
`meta`), empty for none. Auto-repeat is suppressed: you get one press and one release per
physical key press. `on_key_release` is useful for “hold to accelerate” mechanics.

The key events are not forwarded while a text `input` is focused.

## Persistent state

`W.state` is a table saved as a Lua literal next to the widget (after every event/tick)
and restored on restart:

```lua
function W.on_click()
    W.state.clicks = (W.state.clicks or 0) + 1
end
```

Supported values: booleans, numbers, strings and nested tables (arrays and maps). Avoid
cycles and functions. Duplicating a widget copies its state file.

The position/size of the widget itself is stored in
`~/.local/state/quickshell/user/desktop-widgets.json`; scripts only own `state`.

## Host helpers

Available as `desktop.*`:

| helper | effect |
|---|---|
| `desktop.notify(title, body)` | Desktop notification (`notify-send`). |
| `desktop.spawn(command, arg1, ...)` | Run a program. A table of arguments also works. |
| `desktop.open(path)` | Open a file/folder with the default application. |
| `desktop.tr(key)` | Translate via the add-on’s language tables; unknown keys pass through. |
| `desktop.log(...)` | Write to stderr. `print(...)` does the same. |
| `desktop.home` | `$HOME`. |
| `desktop.dir`, `desktop.script_path` | Directory of the running script and its full path — use them to locate your own assets. |
| `desktop.strings` | The current translation dictionary. |

Translations are delivered right after `init`, followed by one repaint, so the first
frame may briefly show untranslated keys.

## Sizing and dragging

- The declared `width`/`height` is applied automatically; changing them at runtime
  resizes and restarts the widget.
- The top **34 px** of a Lua widget belong to the drag handle, so mouse events there
  move the card instead of reaching the script. Draw content below that line.
- Right-click anywhere opens the widget menu.
- Built-in clock/calendar/date-time widgets set `drag = "all"` in their widget record,
  which makes the whole card draggable; widgets with interactive bodies keep the strip.

## Assets and licensing

Scripts can load their own PNGs with the `image` operation, for example:

```lua
local dir = (desktop.dir or ".") .. "/my-game-assets"
local function asset(name)
    local f = io.open(dir .. "/" .. name, "rb")
    if f then f:close(); return "file://" .. dir .. "/" .. name end
end
```

Do not redistribute copyrighted game art. The bundled `docs/examples` use only vector
graphics or original placeholder art.

## Errors and debugging

Run a script without the shell:

```bash
cd ~/.config/quickshell/ii/modules/ii/background/desktop
printf 'i\t300\t130\tdigital\ttest\n' | lua lua/host.lua lua/widgets/clock.lua
```

The host prints one JSON line per command (ops, metadata, actions), which is handy to
check mistakes.

- `render` errors are caught and drawn on the widget as a red error card; the full
  message goes to stderr.
- Syntax/runtime errors while loading the script terminate the process; the widget stays
  empty and `lua widget exited: …` appears in the shell log. Fix the file, then
  right-click → **Reload script**.
- `qs` logs: start the shell in a terminal or check the log path printed at startup.
  Errors from Lua callbacks appear as `lua widget <id>: …`.

## Performance

- A repaint rebuilds the whole operation list. Keep `render` simple and avoid allocating
  large tables every frame if `tick` is low.
- Use `tick = 0` unless the widget really animates; a 1 s tick is enough for clocks.
- Bitmap drawing (`paint.lua`) emits one line op per segment; thin out points
  (`distance >= 2 px`) to keep the list small.
- Each instance has its own Lua process, so many animated widgets cost more CPU.

## Examples

Ready-made scripts, all using the API above:

- `lua/widgets/clock.lua` — vector analog clock, digital/minimal text layout;
- `lua/widgets/calendar.lua` — month grid with today marker, compact variant;
- `lua/widgets/datetime.lua` — stacked/inline date and time;
- `lua/widgets/notes.lua` — `input` op, rotation, per-instance state;
- `lua/widgets/timer.lua` — dynamic tick, hit-testing, notifications, spawning Clocks;
- `lua/widgets/paint.lua` — pointer strokes, palette, persistent drawing;
- `docs/examples/hello.lua` — minimal click counter with animation;
- `docs/examples/minesweeper.lua` — complete 9×9 game: persistent state, first-click
  safety, flood reveal, flags (middle click or flag mode), timer, win/lose overlays;
- `docs/examples/snake.lua` — animated game loop driven by `on_tick`: dynamic speed,
  arrows/WASD steering, click/d-pad fallback, pause on blur, score and best score;
- `docs/examples/desktogeddon.lua` — DesktoGeddon, a top-down car game: vector car and pedestrians,
  physics in Lua, splats/particles, timer and best score;
- `docs/examples/desktocraft.lua` — DesktoCraft, a first-person voxel sandbox:
  software 3D renderer with `quad` faces, procedural world, collision,
  mining/building and persistence;
- `docs/examples/airhockey.lua` — air hockey: hover-driven paddle, keyboard
  fallback, circle physics, AI opponent, match scoring and persistent wins.

A minimal widget:

```lua
local W = { width = 280, height = 140, tick = 0 }

function W.render(w, h)
    return {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 16,
          color = "rgba(18,18,21,0.74)", border = 1,
          borderColor = "rgba(255,255,255,0.10)" },
        { type = "text", x = w / 2, y = h / 2, text = "Hello!",
          size = 22, color = "#ffffff", align = "center", valign = "middle" },
    }
end

return W
```
