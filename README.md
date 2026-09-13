# Minecraft → Xeneon Edge HUD

Live Minecraft dashboard on the Corsair Xeneon Edge touchscreen in a kiosk browser (or as iCUE widgets),
fed by the [JourneyMap](https://modrinth.com/mod/journeymap) webmap API
(`http://localhost:8080`). Works with solo worlds **and Realms**, on any
Minecraft version JourneyMap supports (Fabric here; JourneyMap also ships
Forge/NeoForge builds if you ever switch loaders).

## Default layout

The dashboard is a configurable grid ([dashboard/config.js](dashboard/config.js),
documented in [dashboard/README.md](dashboard/README.md)). Out of the box it is
a 16 × 9 grid with the map in the middle and three panels down each side:

```
┌─────────┬───────────────────────────────┬─────────┐
│  Clock  │                               │         │
│day/night│                               │Waypoints│
├─────────┤                               │direct-to│
│ Coords  │           Live Map            │         │
│ (live)  │  mobs · animals · villagers   ├─────────┤
├─────────┤  players · waypoints          │ Environ-│
│ Coords  │                               │  ment   │
│ (tap)   │                               │         │
└─────────┴───────────────────────────────┴─────────┘
```

- **MC Live Map** (`widgets/map`) — chrome-free map centered on you with
  JourneyMap's radar drawn on it: hostile mobs (red ring), animals, villagers and
  other players (skin face and name), plus your waypoints with death points marked.
  Auto mode shows the night layer after dark and the cave layer underground (always
  in the Nether). Zoom, mode and layers are parameters.
- **MC Coordinates** (`widgets/coords`) — X/Y/Z, dimension, facing; updates twice a second.
- **MC Coordinates (tap)** (`widgets/coords-tap`) — updates **only when tapped**;
  shows the capture time. Use it to pin a spot (portal, base, drop chest) while you keep moving.
- **MC Day/Night Clock** (`widgets/clock`) — in-game time with the sun/moon on an arc,
  countdown to nightfall or dawn, and when the bed works.
- **MC Waypoints** (`widgets/waypoints`) — your JourneyMap waypoints by distance, with
  height difference and an arrow relative to where you face; death points pinned in red;
  tap a row to keep it on top.
- **MC Environment** (`widgets/environment`) — biome, the Nether/Overworld portal
  coordinates for where you stand, chunk and region.

Change the grid, move panels, add a second map or a web page: edit
`dashboard/config.js` and the running dashboard picks it up within seconds.
All the options, examples and limitations are in [dashboard/README.md](dashboard/README.md).

## Setup

### 1. Mods (re-run after every Minecraft update)

```powershell
.\scripts\install-mods.ps1
```

Detects your newest Fabric profile, installs the matching **JourneyMap**,
**JourneyMap WebMap** and a **borderless fullscreen** mod (Cubes Without
Borders, or Borderless Mining on older versions) from Modrinth, sets
`pauseOnLostFocus:false`, and pins the webmap to port 8080 (the port pin needs
one game launch first — run the script again after that).

Prereq: the [Fabric loader](https://fabricmc.net/use/installer/) profile for
your Minecraft version. That's the only thing this project needs per-version —
everything else is version-independent.

### 2. Focus guard (one-time)

```powershell
.\scripts\install-tasks.ps1
```

Registers `focus-guard.ps1` (and the dashboard launcher from step 3) as hidden at-logon tasks and starts them. When a tap
on the Edge steals focus from Minecraft, it gives focus straight back and snaps
the cursor to where it was — the widget still gets the tap, the game never
minimizes or loses input. Only the ultra-wide (32:9) monitor is guarded;
the other monitors behave normally. Remove with `-Uninstall`.

The borderless fullscreen mod (installed in step 1) keeps the game
full-screen-borderless so even a stolen focus can't minimize it. In Minecraft's
video settings, use its borderless toggle instead of vanilla fullscreen.

### 3. Dashboard on the Edge

In iCUE, turn **off "Show iCUE Widgets"** for the Xeneon Edge so it behaves as
a normal 2560x720 monitor. Then:

```powershell
.\scripts\start-dashboard.ps1
```

opens [dashboard/index.html](dashboard/index.html) as a fullscreen kiosk browser
window (Edge/Chrome with its own profile, pinch/swipe disabled) on the 32:9
monitor. Step 2's task installer also registers it to open automatically at logon
(`MinecraftHUD-Dashboard`). `-Restart` reopens it, `-Stop` closes it.

The layout and every widget setting live in [dashboard/config.js](dashboard/config.js);
see [dashboard/README.md](dashboard/README.md). Saving the file updates the
running dashboard, and mistakes are reported in a banner on the screen.

<details>
<summary>Alternative: iCUE widgets instead of the kiosk browser</summary>

`.\scripts\package-widgets.ps1` builds `dist\*.icuewidget` files for all six
widgets. Import the ones you want in **iCUE → Xeneon Edge → Widgets** (+ button)
and arrange them in iCUE's 3 × 2 slot grid (for example MC Live Map → Large in
columns 1–2, MC Coordinates → 3a, MC Coordinates (tap) → 3b). Same widgets, same
data — just rendered by iCUE instead of a browser; `dashboard/config.js` does
not apply there and widget settings are set in iCUE.
</details>

### Day-to-day

Nothing. Launch Minecraft (solo or Realms), join a world, and the panels light
up; quit and they show "Minecraft not running". The guard task idles when the
game is closed.

## How it works

- JourneyMap maps client-side, so Realms works; its WebMap addon serves an
  unauthenticated localhost REST API: `/data/player` (position/heading/biome),
  `/data/world` (dimension, time), `/data/waypoints`, `/data/all?images.since=`
  (changed map regions), `/tiles/tile.png` (512px region tiles). The map widget
  bundles Leaflet (`CRS.Simple`, native zoom 0, 1 block = 1 map unit) and
  re-fetches only regions JourneyMap re-rendered.
- `widgets/jm-api.js` is the shared API helper. Each widget folder carries its
  own copy because iCUE imports widgets as standalone packages; after editing
  the canonical file run `scripts\sync-jm-api.ps1` (the packager does it too).
- `dashboard/index.html` reads `dashboard/config.js` and builds a CSS grid of
  iframes, one per panel, passing each widget its settings as URL parameters.
  It re-reads the config every few seconds (loading it as a script, since a
  `file://` page cannot `fetch()` local files) and rebuilds when it changed.
- The Edge is a real Windows display even in dashboard mode, so touches *do*
  reach Windows — that's why the focus guard exists.

## Troubleshooting

- **Widgets say "Minecraft not running" in-game** — check
  `http://localhost:8080/data/player` in a browser. If the port differs
  (JourneyMap picks a free one if 8080 is busy), either re-run
  `install-mods.ps1` after a launch to pin it, or set `apiBase` in
  `dashboard/config.js`.
- **Map is black in a new area** — JourneyMap only maps where you've been;
  give it a few seconds after entering a world.
- **Red banner on the dashboard** — a problem in `dashboard/config.js`; it
  says which panel and what. See [dashboard/README.md](dashboard/README.md).
- **Tap minimizes the game anyway** — is the focus guard task running?
  `Get-ScheduledTask MinecraftHUD-FocusGuard` should say Running; re-run
  `scripts\install-tasks.ps1`. Also make sure the game uses Borderless
  Fullscreen, not vanilla fullscreen.
- **New Minecraft version, no JourneyMap build yet** — the installer says so
  explicitly. Play the older version until JourneyMap updates (usually days).

## Repo layout

- `widgets/` — the HUD panels (plain HTML; also packageable as iCUE widgets) and
  the canonical `jm-api.js`
- `dashboard/` — kiosk page, its `config.js` layout, and the configuration README
- `scripts/` — installer, packager, `jm-api.js` sync, focus guard, task registration,
  dashboard launcher
- `attic/` — retired first iteration: custom Fabric mod (`icuehud`, version-pinned
  HTTP server) + inventory widget that read from it. Superseded by JourneyMap.
