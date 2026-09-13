# Dashboard configuration

The dashboard is one page, [index.html](index.html), that reads
[config.js](config.js) and lays out widgets on a grid. Everything you can
change lives in `config.js`; you never need to touch `index.html`.

Edit `config.js` and save. The running dashboard re-reads it every few seconds
and rebuilds only when something changed, so you can tweak the layout while
you play and watch it happen on the Edge. Mistakes show up as a red banner at
the top of the screen that names the panel and the problem; the rest of the
layout keeps working.

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
| `watchConfig`     | boolean | `true`                  | re-read `config.js` while running |
| `watchInterval`   | ms      | 3000                    | how often to re-read it (500 minimum) |
| `panels`          | array   | required                | the panels, see below |

`gap`, `padding` and `radius` also accept CSS strings such as `"0.5vw"`.

### Panel

| key          | type    | default | meaning |
|--------------|---------|---------|---------|
| `widget`     | string  |         | folder name under `widgets/` (`map`, `coords`, `coords-tap`, `clock`, `waypoints`, `environment`), or `empty` for a blank panel |
| `url`        | string  |         | instead of `widget`: any page to show in the panel (`file:///…`, `https://…`) |
| `col`, `row` | 1..     | auto    | top-left cell; give both or neither |
| `colSpan`    | 1..     | 1       | width in cells |
| `rowSpan`    | 1..     | 1       | height in cells |
| `params`     | object  | `{}`    | widget settings, see the widget list (become `?key=value` on the widget URL) |
| `background` | color   |         | this panel's background |

The same widget can appear more than once with different `params` (two maps
at different zooms, for example).

## Widgets

All widgets read the JourneyMap webmap API at `apiBase`, show "Minecraft not
running" when it is unreachable, and take `apiBase` as a parameter if one
panel needs a different address.

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
| `zoomLevel` | `-2` (far) … `5` (close)                     | `2`     | |
| `mapMode`   | `auto`, `day`, `night`, `topo`               | `auto`  | a fixed layer, or follow the game |
| `entities`  | `all`, `none`, or a list like `mobs,players` | `all`   | which radar lists to draw (`mobs`, `animals`, `villagers`, `players`) |
| `waypoints` | `1`, `0`                                     | `1`     | draw waypoints |
| `labels`    | `all`, `players`, `waypoints`, `none`        | `all`   | which markers get a name label (death points always do) |
| `autoNight` | `1`, `0`                                     | `1`     | in auto mode, switch to the night layer after dark |
| `autoCaves` | `1`, `0`                                     | `1`     | in auto mode, switch to the cave layer underground |

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
boat. No parameters.

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

### `environment` — biome, portal link, chunk

The biome you stand in, tags for dimension / underground / sneaking, the
coordinates a Nether portal built here would link to (÷ 8 in the Overworld,
× 8 in the Nether, nothing in the End), and your chunk, position within the
chunk and region. No parameters.

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
5. Add `manifest.json` and a 256×256 `icon.png` only if you want
   `scripts\package-widgets.ps1` to build an iCUE package for it.

## Limitations

- **Only what JourneyMap knows.** The webmap API exposes position, heading,
  biome, underground/sneaking flags, world time and name, waypoints, and the
  radar lists (mobs, animals, villagers, other players in render distance).
  It does *not* expose health, hunger, XP, inventory, armor, held item,
  effects, weather, light level or server TPS. Those would need a client mod
  again (the retired one in `attic/` did inventory).
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
- **Layout did not update** — `watchConfig` is `false`, or the file still
  has an error (banner). `scripts\start-dashboard.ps1 -Restart` always works.
