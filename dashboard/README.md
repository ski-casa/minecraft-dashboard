# Dashboard configuration

The dashboard is one page, [index.html](index.html), that lays out widgets
on a grid. You arrange it **on the screen itself**; [config.js](config.js)
is the starting layout and a way to carry a layout to another machine.
You never need to touch `index.html`.

## Arranging the screen

Tap the dim **⚙** in the bottom-left corner. The screen switches to edit
mode: every panel gets a title bar, a resize corner, and the grid cells
show through.

- **Move** a panel by dragging it; **resize** by dragging the striped corner.
  Panels snap to the grid and cannot overlap: a spot that does not fit shows
  red and the panel springs back when you let go.
- **⚙ on a panel** opens its settings (the same `params` as below, as a
  form, plus its size in cells). **✕** removes it.
- **＋ Add widget** lists every widget with a short description, in tabs:
  *Map & navigation*, *Inventory & gear*, *Status*, *Tools* (touch-driven
  helpers) and *Other* ("Web page" for any URL, "Empty panel"). The new panel
  takes the first free space that fits its usual size, shrinking if it must;
  move it where you want it.
- **Screen** sets the grid (columns × rows), gap, edge, corner radius, colors
  and the two API addresses. Changing the grid rescales every panel to keep
  its place, so going from 16 × 9 to 32 × 18 just doubles the resolution of
  the snapping. At the bottom it lists your **monitors**: tap one to move
  the dashboard there (the kiosk window closes and reopens on that monitor
  in a few seconds, and opens there from then on). This needs the small
  control service that `scripts\start-dashboard.ps1` runs alongside the
  browser (`scripts\dashboard-control.ps1`, on `localhost:27422`); without
  it the list says so and the command-line way is
  `start-dashboard.ps1 -Monitor <n> -Remember`. Note that the focus guard
  only protects Minecraft from taps on the 32:9 monitor.
- **Layout…** downloads the layout as a `config.js`, copies it to the
  clipboard, lets you paste one in, or resets to `config.js`.
- **Done** (or Esc) leaves edit mode. If you changed anything it asks
  whether to **save the layout under a name** (a timestamp by default, or
  the name of the layout you were editing, to update it in place).

### Saved layouts

Every change is saved at once as the *working layout* of the monitor you
are on, in the kiosk browser's profile, and is back after a restart. Each
monitor keeps its own working layout, so moving the dashboard to another
monitor, arranging it there and moving back brings each one's own
arrangement.

Named layouts are the ones you keep: **Done → Save**, or **Screen → Saved
layouts → Save current as…**. They are files in `dashboard\layouts\<name>.json`
(written by the control service; when it is not running they are kept in the
browser instead and the list says so). Each records the screen it was made
on, and the list under **Screen** shows this monitor's layouts first, marked
"this monitor"; others show their screen size. Tap one to load it (it
replaces what is on screen; on a different screen it is scaled to the grid
there), **✕** to delete it. The layout you loaded last is marked as current.

To take a layout to another PC, copy its file into that PC's
`dashboard\layouts\`, or use **Layout… → Download as config.js** and drop it
in as `config.js` to make it the starting layout.

Your saved layouts are personal and git-ignored. `dashboard\layouts\samples\`
has two to start from, one for the 2560 × 720 Edge (the same arrangement as
`config.js`) and one for a 16:9 monitor: copy a file up into
`dashboard\layouts\` and it appears under **Saved layouts**.

Where the layout comes from, in order: the one saved by the editor; otherwise
`config.js`; otherwise a built-in default when `config.js` is missing or
broken. While no layout is saved, `config.js` is re-read every few seconds
and hand edits apply live, as before. Once you have edited on screen,
`config.js` is only used by **Reset to config.js**.

The grid is what makes the layout screen-independent: panels are placed in
cells, not pixels, so the same layout fills a 2560 × 720 Edge or a 1920 × 1080
monitor. Different shapes still want different arrangements, so on a new
screen open the editor, pick a grid that suits it (**Screen**), shuffle, and
save it under a name; it is listed for that monitor from then on.

Widgets, their descriptions and their settings forms come from
[widgets.js](widgets.js); add an entry there for a widget of your own.

## Writing config.js by hand

Everything below is still valid: `config.js` is a plain JavaScript object
that the editor reads, writes and understands. Mistakes show up as a red
banner at the top of the screen that names the panel and the problem; the
rest of the layout keeps working.

## The grid

The screen is divided into `grid.columns` × `grid.rows` equal cells, and
every panel is a rectangle of whole cells: it starts at `col`/`row` (counted
from 1, top-left) and covers `colSpan` × `rowSpan` cells.

```
grid: { columns: 16, rows: 9 }        col: 1-3      4-13         14-16
                                            ┌────────┬──────────────┬────────┐
{ widget: "map", col: 4, row: 1,     row 1  │ clock  │              │        │
  colSpan: 10, rowSpan: 9 }                 │        │              │ way-   │
                                     row 4  ├────────┤     map      │ points │
{ widget: "waypoints", col: 14,             │ coords │              │        │
  row: 1, colSpan: 3, rowSpan: 5 }   row 6  │        │              ├────────┤
                                     row 7  ├────────┤              │ envir- │
                                            │  tap   │              │ onment │
                                     row 9  └────────┴──────────────┴────────┘
```

Which grid to use is up to you. Cell sizes on the 2560×720 Edge with the
default 8px gap and padding:

| grid    | one cell  | what a "normal" panel is                       |
|---------|-----------|------------------------------------------------|
| 4 × 2   | 630 × 348 | 1 × 1                                          |
| 8 × 4   | 311 × 170 | 2 × 2                                          |
| 16 × 9  | 151 × 71  | 3 × 3 side panels, 10 × 9 map (the default)    |
| 16 × 8  | 151 × 81  | 4 × 4                                          |

A finer grid lets you carve out half- or quarter-size panels without
changing every other panel. The default is 16 × 9: three-column side panels
(about 470 px wide) flanking a ten-column map. A single cell there is only
151 × 71 px, enough for one number, not a whole widget; 2 × 2 (about
310 × 150) is the practical minimum for the clock or the coordinates. All
widgets scale their text from the panel's smaller side, so a tiny panel gets
tiny text rather than a clipped one.

Panels must not overlap and must fit inside the grid; the banner tells you
when they do not. Leave `col` and `row` out and the panel is auto-placed
into the first free cells that fit its span (handy for "just add it
somewhere"), but explicit placement is easier to reason about.

## Reference

### Top level

| key               | type    | default                 | meaning |
|-------------------|---------|-------------------------|---------|
| `grid.columns`    | 1..64   | 16                      | number of grid columns |
| `grid.rows`       | 1..64   | 9                       | number of grid rows |
| `gap`             | px      | 8                       | space between panels |
| `padding`         | px      | 8                       | space around the whole grid |
| `radius`          | px      | 10                      | panel corner radius |
| `background`      | color   | `"#000"`                | screen background |
| `panelBackground` | color   | `"#101014"`             | panel background; also what shows while a widget loads |
| `apiBase`         | URL     | `"http://localhost:8080"` | JourneyMap webmap address, passed to every widget |
| `modApiBase`      | URL     | `"http://localhost:27421"` | iCUE HUD Bridge mod address (`armor`, `materials`), passed to every widget |
| `watchConfig`     | boolean | `true`                  | re-read `config.js` while running |
| `watchInterval`   | ms      | 3000                    | how often to re-read it (500 minimum) |
| `panels`          | array   | required                | the panels, see below |

`gap`, `padding` and `radius` also accept CSS strings such as `"0.5vw"`.

### Panel

| key          | type    | default | meaning |
|--------------|---------|---------|---------|
| `widget`     | string  |         | folder name under `widgets/` (see [Widgets](#widgets)), or `empty` for a blank panel |
| `url`        | string  |         | instead of `widget`: any page to show in the panel (`file:///…`, `https://…`) |
| `col`, `row` | 1..     | auto    | top-left cell; give both or neither |
| `colSpan`    | 1..     | 1       | width in cells |
| `rowSpan`    | 1..     | 1       | height in cells |
| `params`     | object  | `{}`    | widget settings, see the widget list (become `?key=value` on the widget URL) |
| `background` | color   |         | this panel's background |

The same widget can appear more than once with different `params` (two maps
at different zooms, for example).

Every widget except the map sizes its text from the panel's smaller side, so
a wide, short panel gets small text. `params: { fontScale: 1.3 }` makes any
widget's text (and pictures) 30 % larger; `0.8` smaller.

## Widgets

Most widgets read the JourneyMap webmap API at `apiBase`, show "Minecraft not
running" when it is unreachable, and take `apiBase` as a parameter if one
panel needs a different address. `armor` and `materials` instead read the
repo's own client mod at `modApiBase` (see [Mod-backed widgets](#mod-backed-widgets)).

### `map` — live map

Chrome-free JourneyMap map centered on you, rotating arrow for your heading.
Follows you across dimensions and re-fetches only the regions JourneyMap
re-rendered. On top of the tiles it draws:

- **Entities** from JourneyMap's radar, once a second: hostile mobs (red
  ring), animals, villagers and other players. Each uses JourneyMap's own
  sprite for that mob; players show their skin face and name. Everything
  within your render distance is included, invisible entities are skipped.
  The badge in the corner counts hostiles.
- **Waypoints** as colored diamonds with their names; death points are a red
  ☠ and always labeled. Only the current dimension's waypoints are drawn.
- **Auto layer switching** (`mapMode: "auto"`): the surface by day, the
  night layer between ticks 13000 and 23000, the cave layer at your Y when
  JourneyMap says you are underground, and always the cave layer in the
  Nether. The badge shows which layer is up.

| param       | values                                       | default | meaning |
|-------------|----------------------------------------------|---------|---------|
| `zoomLevel` | `-2` (far) … `5` (close)                     | `2`     | starting zoom |
| `zoomButtons` | `true`, `false`                            | `true`  | tap + / − buttons in the bottom-right corner (pinch also zooms) |
| `zoomReset` | seconds, `0` = never                         | `0`     | after a manual zoom, return to `zoomLevel` once the map is left alone this long |
| `mapMode`   | `auto`, `day`, `night`, `topo`               | `auto`  | a fixed layer, or follow the game |
| `entities`  | `all`, `none`, or a list like `mobs,players` | `all`   | which radar lists to draw (`mobs`, `animals`, `villagers`, `players`) |
| `mobs`, `animals`, `villagers`, `players` | `true`, `false`       | `true`  | switch one entity type off (applied after `entities`) |
| `waypoints` | `1`, `0`                                     | `1`     | draw waypoints |
| `labels`    | `all`, `players`, `waypoints`, `none`        | `all`   | which markers get a name label (death points always do) |
| `autoNight` | `1`, `0`                                     | `1`     | in auto mode, switch to the night layer after dark |
| `autoCaves` | `1`, `0`                                     | `1`     | in auto mode, switch to the cave layer underground |
| `trail`     | minutes, `0` = off                           | `0`     | draw the path you walked in the last N minutes (a blue line) |
| `centerX`, `centerZ` | block coordinates                   |         | **base cam**: keep the map on a fixed spot instead of following you (your arrow still moves) |

At zoom 2 one block is 4 px, so a 640 px wide panel shows 160 blocks across.
The map is deliberately not draggable or pinchable (touches would fight the
game); it is always north-up. Radar categories must also be enabled in
JourneyMap's own options (Radar → mobs, animals, villagers, players); the
widget skips any that are off.

### `coords` — live coordinates

X / Y / Z, dimension and facing, twice a second. No parameters.

### `coords-tap` — captured coordinates

Blank until tapped; each tap stores your position at that moment with the
time. Use it to pin a portal, a hole you fell into, or where you left the
boat. With the iCUE HUD Bridge mod installed, pressing **H** in game does the
same without reaching for the screen (the action bar echoes the captured
position), and the last capture survives a dashboard reload.

| param    | values     | default | meaning |
|----------|------------|---------|---------|
| `hotkey` | `1`, `0`   | `1`     | listen for the in-game key (needs the mod; taps always work) |

The key is ignored while a menu or chat is open. To use another key, edit
`capture=H` in `.minecraft\config\icuehud\keys.properties` (see
[Hotkeys](#hotkeys)).

### `clock` — day/night clock

In-game time with the sun or moon on an arc, the phase (Day / Dusk / Night /
Dawn), a countdown to nightfall (surface mobs start spawning at tick 13000)
or to dawn (23000), how long until the bed works (12542) and the raw tick.
The countdown turns orange in the last minute before night. If the day
counter is shown depends on JourneyMap reporting the full world time rather
than the time of day.

| param        | values     | default |
|--------------|------------|---------|
| `hourFormat` | `24`, `12` | `24`    |

### `waypoints` — direct-to waypoints

Your JourneyMap waypoints (the ones you make with **B** in game) sorted by
distance, each with the distance in blocks, the height difference (↑ / ↓)
and an arrow that points the way *relative to where you are facing*: straight
up means "walk forward", and it turns green when you are within 12° of the
line. Death points are red with a ☠ and pinned to the top. Tap a row to keep
it at the top while you travel; tap again to release it. Disabled waypoints
are hidden.

| param        | values           | default   | meaning |
|--------------|------------------|-----------|---------|
| `dimensions` | `current`, `all` | `current` | `all` also lists other dimensions' waypoints, tagged with their dimension; Nether/Overworld ones are measured at their portal-linked coordinates (÷ 8 / × 8) |
| `maxRows`    | number           | `12`      | rows to render (extra rows are clipped by the panel height anyway) |
| `deathFirst` | `1`, `0`         | `1`       | pin death points above everything else |

### `threats` — hostile mobs as a list

JourneyMap's radar hostiles (the same ones the map draws) sorted by
distance, each with its sprite, the distance in blocks, the height
difference and an arrow relative to where you face. Red under 8 blocks,
orange under 16; the header counts them.

| param     | values            | default | meaning |
|-----------|-------------------|---------|---------|
| `maxRows` | number            | `8`     | rows to show (nearest first) |
| `range`   | blocks, `0` = all | `0`     | ignore anything farther than this |

### `environment` — biome, portal link, chunk

The biome you stand in, tags for dimension / underground / sneaking, the
coordinates a Nether portal built here would link to (÷ 8 in the Overworld,
× 8 in the Nether, nothing in the End), and your chunk, position within the
chunk and region. No parameters.

### `timers` — countdowns and a stopwatch

Tap a timer to start it, tap again to pause, **↺** to reset; a finished
countdown flashes red until reset. Timers keep running across a dashboard
reload. No mod needed.

| param     | values                          | default |
|-----------|---------------------------------|---------|
| `presets` | `Name|m:ss; Name|m:ss; …`, `0` = stopwatch | `Furnace x64|10:40; Brewing|0:20; Stopwatch|0` |

### `checklist` — steps to tick off

A list from the `items` parameter; tap to tick, "Uncheck all" to start over.
Ticks are remembered per list. No mod needed.

| param   | values                   | default                                  |
|---------|--------------------------|------------------------------------------|
| `title` | text                     | `Checklist`                              |
| `items` | `step; step; …`          | `Pack food; Torches; Water bucket; Bed` |

## Mod-backed widgets

JourneyMap knows nothing about your inventory or your condition, so these
widgets read the **iCUE HUD Bridge** mod in `mod/` (build and install it with
`scripts\build-mod.ps1`; it serves `http://localhost:27421/state`). Without
the mod they show "HUD mod not running"; outside a world, "Not in a world";
with a mod older than the widget, "Mod update needed".

### `armor` — equipment durability

One row per slot: the item's picture, its name, remaining durability as a
bar and as `left/max`. Bar colors: green 50–100 %, yellow 25–49 %, orange
10–24 %, red 1–9 % (pulsing). An empty slot shows a red ✕. Items without
durability (a carved pumpkin, a totem in the off hand) get a grey bar.

| param       | values                                          | default                 | meaning |
|-------------|-------------------------------------------------|-------------------------|---------|
| `slots`     | list from `head, chest, legs, feet, mainhand, offhand` | `head,chest,legs,feet` | rows to show, in this order; add `mainhand` to watch the tool you hold |
| `showNames` | `true`, `false`                                 | `true`                  | item name next to the slot label |
| `title`     | text                                            | `Durability`            | heading; `""` for none |

### `materials` — build project progress

A list of materials with `have/need` for each, where *have* counts your
inventory (blue part of the bar) plus everything in the chests the mod
tracks (green). A line turns green with a ✓ once you have enough.

```js
{ widget: "materials", col: 11, row: 5, colSpan: 3, rowSpan: 5, params: {
    items: "smooth_stone:1242, white_stained_glass:418"
} },
```

`items` is `name:amount` pairs separated by commas. Names are Minecraft item
ids without the `minecraft:` prefix (`smooth_stone`, `white_stained_glass`,
`oak_log`; spaces instead of underscores also work). Edit and save to change
the list or the targets; the running dashboard picks it up.

**Which chests count.** Only storage you placed yourself: chests, trapped
chests, barrels and shulker boxes. The mod notices when you place one and
tracks it from then on; breaking it forgets it. A chest you *find* (a
mineshaft, a village) is ignored, but you can claim any chest by pressing
**K** while it is open (the action bar says whether it is counted; K again
un-claims). Use that once for storage you built before installing the mod.
A double chest is one entry, counted once.

**How counting stays right.** The game only tells your client what is in a
chest while it is open, so the mod records a chest's contents every time you
open it and remembers them per world in `.minecraft\config\icuehud\`
(`containers-sp_<world name>.json`, `containers-realm_<realm name>.json` or
`containers-mp_<address>.json`), so they survive closing the game. Taking
items out or putting them in updates both the chest and inventory sides at
once, so nothing is counted twice or dropped. What it *cannot* see is a chest
changed while closed (a hopper feeding it, another player); that shows up the
next time you open it.

| param      | values                | default     | meaning |
|------------|-----------------------|-------------|---------|
| `items`    | `name:amount, …`      |             | the list; without it the panel says how to set it |
| `title`    | text                  | `Materials` | heading; `""` for none |
| `hideDone` | `true`, `false`       | `false`     | hide items once you have enough |
| `sort`     | `list`, `remaining`   | `list`      | as written, or most-missing first |

The footer shows how many chests are tracked, or, while a chest is open,
whether it is counted (with the key hint if not).

### `effects` — potion effects with timers

One row per active effect: its icon, name and level, time left and a bar.
Running-out effects jump to the top and turn red in the last `warnSeconds`
(Fire Resistance, Water Breathing, Slow Falling, Invisibility and Conduit
Power always warn; harmful effects count down in orange). Infinite effects
(a beacon) show ∞. A small row above shows ♥ health, food, air when diving,
XP level and 🔥 when on fire.

| param         | values          | default   | meaning |
|---------------|-----------------|-----------|---------|
| `title`       | text            | `Effects` | heading; `""` for none |
| `warnSeconds` | seconds         | `30`      | when "running out" starts |
| `showVitals`  | `true`, `false` | `true`    | the health / food / air row |

### `death` — death recovery

Where you last died (the mod records it the moment it happens, per world,
and remembers it across relogs), the distance and an arrow relative to where
you face, the height difference, and a countdown until the items you dropped
despawn (five minutes while their chunk is loaded; after that the panel says
"likely gone"). Hidden an hour after the death unless `hideAfterMinutes` says
otherwise.

| param              | values                 | default |
|--------------------|------------------------|---------|
| `despawnMinutes`   | minutes                | `5`     |
| `hideAfterMinutes` | minutes, `0` = never    | `60`    |

### `light` — light level and spawn risk

The block light where you stand as a lamp (red and pulsing at 0), the
verdict ("Mobs can spawn here" when block light is 0 and the sky is not
keeping them away, "Dark – unsafe after dusk" when daylight is all that
protects the spot, "Lit – no spawns" otherwise), sky light, weather and the
moon phase. No parameters.

### `daycounter` — world day, session, real clock

The world's day number (JourneyMap only exposes the time of day, so the
clock widget cannot show it), how long this Minecraft session has been
running, and the real time. `hourFormat`: `24` or `12`.

### `inventory` — the 36 slots

Your inventory as a 9-wide grid with item pictures, counts and durability
bars, and the number of free slots in the corner (red when two or fewer).
`hotbar`: `bottom` (like the game), `top` or `hide`.

### `xp` — level and enchanting

Level and progress to the next, lapis in your inventory (and how many
enchants that is), gold once `target` (default 30) is reached.

### `flight` — elytra

Elytra durability, rockets in your inventory, altitude, horizontal speed,
climb/sink rate and heading; the header says "gliding" while you are.
Elytra "not worn" and zero rockets show orange/red. No parameters.

### `connection` — ping and FPS

Your latency to the server or Realm ("local" in single player) and the
client's frame rate, colored green / orange / red. No parameters.

### `actions` — quick actions

Big buttons that act in the game through the mod. Each button is
`Label|action:text`, separated by `;`:

| action        | does                                                             | example |
|---------------|------------------------------------------------------------------|---------|
| `key:<KEY>`   | presses a key binding once (JourneyMap's **B** = new waypoint, **J** = full map, your own binds) | `Mark here|key:B` |
| `chat:<text>` | says something in chat                                           | `Heading home|chat:heading home` |
| `command:<cmd>` | runs a command (leading slash optional)                        | `Spawn|command:spawn` |
| `capture`     | stamps your position onto the coords-tap panel (same as the capture key) | `Capture|capture` |
| `perspective` | cycles first / third person                                      | `View|perspective` |
| `screenshot`  | takes a screenshot                                               | `Shot|screenshot` |
| `message:<text>` | shows text on your own action bar only                        | `Note|message:torches!` |

Key names are Minecraft's (`A`–`Z`, `F1`–`F24`, `NUMPAD0`…), the same as in
[Hotkeys](#hotkeys). A button flashes green when the mod took the action, red
when it could not reach it. `columns` fixes the number of columns (`0` =
automatic); `title` adds a heading. The focus guard gives focus back to the
game after the tap, so the key or chat lands in the game as if you pressed it.

### Hotkeys

The mod's two keys are set in `.minecraft\config\icuehud\keys.properties`,
which the mod creates on its first launch:

```properties
capture=H          # stamp your position onto the coords-tap panel
trackContainer=K   # while a chest is open: count it for materials (again to un-count)
```

Names are Minecraft's own: `A`–`Z`, `0`–`9`, `F1`–`F24`, `NUMPAD0`–`NUMPAD9`,
`HOME`, `END`, `INSERT`, `PAGEUP`, `PAGEDOWN`, `LBRACKET`, `RBRACKET`,
`SEMICOLON`, `APOSTROPHE`, `GRAVE`, `MINUS`, `EQUALS`, `BACKSLASH`, and so on.
Save the file and the change applies within about five seconds, no restart.
An unknown name is reported in the game log and the previous key stays.
Pick keys that neither Minecraft nor your other mods use (JourneyMap takes
J, B, N, M, `[`, `]`, `\`; Iris uses K on its own screens only).

### `empty`

A blank panel in the panel color. Useful to reserve a slot or keep the
layout symmetric. You can also simply leave cells unused; they show the
screen background instead.

### `url` panels

Any page. Local files work (`file:///C:/…/something.html`) and so do web
pages, unless the site forbids being embedded (many do: YouTube embeds
work, youtube.com itself does not). Web pages get no `apiBase`, and the
kiosk browser has no way to log in to anything, so keep to pages that need
no sign-in.

## Examples

Replace the `panels` array (and `grid` where shown) in `config.js`.

**Simple 4 × 2, no spans**

```js
grid: { columns: 4, rows: 2 },
panels: [
	{ widget: "map",         col: 1, row: 1, rowSpan: 2, params: { zoomLevel: 2 } },
	{ widget: "coords",      col: 2, row: 1 },
	{ widget: "coords-tap",  col: 2, row: 2 },
	{ widget: "clock",       col: 3, row: 1 },
	{ widget: "waypoints",   col: 3, row: 2 },
	{ widget: "environment", col: 4, row: 1 }
]
```

**Map across the whole top, a strip of panels underneath**

```js
grid: { columns: 8, rows: 4 },
panels: [
	{ widget: "map",         col: 1, row: 1, colSpan: 8, rowSpan: 3, params: { zoomLevel: 1 } },
	{ widget: "coords",      col: 1, row: 4, colSpan: 2 },
	{ widget: "coords-tap",  col: 3, row: 4, colSpan: 2 },
	{ widget: "clock",       col: 5, row: 4, colSpan: 2 },
	{ widget: "environment", col: 7, row: 4, colSpan: 2 }
]
```

**Two maps: close-up plus overview**

```js
panels: [
	{ widget: "map", col: 1, row: 1, colSpan: 2, rowSpan: 4, params: { zoomLevel: 3 } },
	{ widget: "map", col: 3, row: 1, colSpan: 2, rowSpan: 4, params: { zoomLevel: -1, mapMode: "topo" } },
	// …
]
```

**Finer grid with a tall waypoint list and small clock**

```js
grid: { columns: 16, rows: 8 },
panels: [
	{ widget: "map",         col: 1,  row: 1, colSpan: 6, rowSpan: 8 },
	{ widget: "coords",      col: 7,  row: 1, colSpan: 4, rowSpan: 3 },
	{ widget: "coords-tap",  col: 7,  row: 4, colSpan: 4, rowSpan: 3 },
	{ widget: "clock",       col: 7,  row: 7, colSpan: 2, rowSpan: 2 },
	{ widget: "environment", col: 9,  row: 7, colSpan: 2, rowSpan: 2 },
	{ widget: "waypoints",   col: 11, row: 1, colSpan: 6, rowSpan: 8, params: { dimensions: "all", maxRows: 20 } }
]
```

**Let the dashboard place things**

```js
panels: [
	{ widget: "map", colSpan: 2, rowSpan: 4 },
	{ widget: "coords", colSpan: 2, rowSpan: 2 },
	{ widget: "clock", colSpan: 2, rowSpan: 2 },
	{ widget: "waypoints", colSpan: 2, rowSpan: 2 },
	{ widget: "environment", colSpan: 2, rowSpan: 2 }
]
```

**A web page in a panel**

```js
{ url: "https://www.youtube.com/embed/jfKfPfyJRdk", col: 7, row: 3, colSpan: 2, rowSpan: 2 }
```

## Adding your own widget

1. Make `widgets/<name>/index.html`. Copy `widgets/jm-api.js` next to it
   (or run `scripts\sync-jm-api.ps1`, which copies it into every widget
   folder) and load it with `<script src="jm-api.js"></script>`.
2. `JM.fetchPlayer()` resolves to `{ x, y, z, heading, facing, dimensionKey,
   dimensionLabel, biome, underground, sneaking, worldTime, … }`;
   `JM.fetchWorld()` and `JM.fetchWaypoints()` give the world and the
   normalized waypoint list; `JM.bearingTo`, `JM.relativeBearing` and
   `JM.distance` do the geometry. Poll with `setInterval`; 500 ms is plenty.
3. Every `?key=value` on the widget URL is exposed as `window.key`, so
   `params: { foo: 1 }` in the config becomes `window.foo` in the widget.
   Add a `<meta name="x-icue-property" …>` line per parameter if you also
   want it configurable in iCUE.
4. Size text with `vmin`/`vw`/`vh` units (`html { font-size: 4.4vmin; }` is
   what the bundled widgets use); the iframe is the widget's viewport, so
   those units are relative to the panel.
5. Add it to [widgets.js](widgets.js) (name, description, usual size, and
   one entry per parameter with its type and default) so it appears in the
   **Add widget** menu with a settings form. A widget missing from the
   catalog still works from `config.js`; its settings then show as plain
   text fields.
6. Add `manifest.json` and a 256×256 `icon.png` only if you want
   `scripts\package-widgets.ps1` to build an iCUE package for it.

## Limitations

- **Only what JourneyMap knows.** The webmap API exposes position, heading,
  biome, underground/sneaking flags, world time and name, waypoints, and the
  radar lists (mobs, animals, villagers, other players in render distance).
  It does *not* expose health, hunger, XP, effects, weather, light level or
  server TPS. Inventory, equipment durability and chest contents come from
  the repo's own mod (`mod/`), which is version-pinned: rebuild it with
  `scripts\build-mod.ps1` after a Minecraft update (bump the versions in
  `mod/gradle.properties` and `mod/src/main/resources/fabric.mod.json`).
- **Chest tracking is client-side.** The `materials` widget sees a tracked
  chest's contents as of the last time you opened it, and tracks only chests
  you placed (or claimed with **K**). Ender chests, hoppers, furnaces and
  minecart chests are not tracked.
- **Waypoints are JourneyMap's.** Vanilla has none. Death points appear when
  JourneyMap's "create death waypoint" option is on (default); they are
  recognized by JourneyMap 5's `type`, or in JourneyMap 6 by a group, icon
  or name containing "death". Waypoints you disable in JourneyMap are hidden
  everywhere; ones with "show on map" off stay in the list but leave the
  map. Verified against JourneyMap 6.0.5; if something looks off, look at
  `http://localhost:8080/data/waypoints` in a browser.
- **Clock accuracy.** JourneyMap reports the time of day (not the world age,
  so there is no day counter) and refreshes it about once a second; the
  widget interpolates at 20 ticks/s in between. When the value stops
  changing for a few seconds (game paused, or the `doDaylightCycle` rule is
  off) the clock shows "frozen" and holds. The bed window assumes clear
  weather; in rain you can sleep a little earlier, but weather is not
  exposed.
- **Radar reach.** Entities on the map are what JourneyMap's radar sees:
  only within your render distance, only the categories enabled in
  JourneyMap's options, and mobs have no name (just their sprite). Icons come
  from JourneyMap's resources; a colored dot stands in when one is missing.
  On servers running the JourneyMap server mod the admin can disable radar
  (a Realm cannot).
- **Panels are isolated.** Each widget is an iframe; they do not talk to each
  other, and the page is opened from `file://`, which is also why the config
  is a `.js` file and not JSON (browsers refuse `fetch()` of local files).
- **Widget code changes need a restart.** Config changes are live; edits to
  a widget's `index.html` show up after `scripts\start-dashboard.ps1 -Restart`
  (or after any config change, which reloads every panel).
- **Wrong widget names are not caught.** The banner reports layout problems,
  unknown keys and bad values, but a misspelled folder just shows the
  browser's "file not found" page inside that panel.
- **iCUE widget mode ignores this file.** If you use the iCUE widgets
  (`scripts\package-widgets.ps1`) instead of the kiosk browser, iCUE's own
  3 × 2 slot grid decides the layout and the per-widget settings are set in
  iCUE. Same widgets, same data.
- **The map is north-up and does not pan by touch.** Heading-up rotation is
  not available (the tiles come pre-rendered).

## Troubleshooting

- **Red banner** — read it; it names the panel index and widget. Common
  ones: `colspan` instead of `colSpan`, two panels on the same cell, a span
  running past the last column, `params` written as a string.
- **"config.js has an error – keeping the last good layout"** — a JavaScript
  syntax error (usually a missing comma or bracket). Fix and save; the
  banner clears on the next check.
- **"Minecraft not running" in every panel** — JourneyMap's webmap is not
  reachable at `apiBase`. Open `http://localhost:8080/data/player` in a
  browser; see the main README's troubleshooting section for the port pin.
- **A panel is blank** — the widget folder name is wrong, or a `url` page
  refuses to be framed.
- **"HUD mod not running" in the armor / materials panels** — the mod is not
  installed for the running Minecraft version, or listens on another port.
  `http://localhost:27421/state` should answer in a world; the game log
  (`.minecraft\logs\latest.log`) has a `[icuehud]` line when it loaded.
  Rebuild with `scripts\build-mod.ps1` after a Minecraft update.
- **An item shows a letter instead of a picture** — pictures come from the
  mod: the item's own sprite from the game files, or for 3D blocks (stairs,
  chests, …) the inventory sprite from the Minecraft Wiki, fetched once and
  kept in `.minecraft\config\icuehud\icons\`. With no internet on the first
  look-up the block's material texture stands in; with nothing at all, a
  letter. The widgets retry every 20 s, so a letter also clears by itself once
  the mod is up. Counting is unaffected.
- **Edits to config.js are ignored** — a layout arranged on screen is in
  charge. **⚙ → Layout… → Reset to config.js** loads the file again (and
  goes back to watching it). Otherwise `watchConfig` is `false`, or the
  file still has an error (banner). `scripts\start-dashboard.ps1 -Restart`
  always works.
- **The layout was lost after a restart** — the kiosk browser must keep its
  profile; the launcher opens it without private mode for that reason. If
  you start the page some other way, avoid `--inprivate` / `--incognito`.
  **Layout… → Download as config.js** is the safe copy.
