# Minecraft → Xeneon Edge HUD

Live Minecraft dashboard on the Corsair Xeneon Edge touchscreen via iCUE widgets,
fed by the [JourneyMap](https://modrinth.com/mod/journeymap) webmap API
(`http://localhost:8080`). Works with solo worlds **and Realms**, on any
Minecraft version JourneyMap supports (Fabric here; JourneyMap also ships
Forge/NeoForge builds if you ever switch loaders).

## Target layout (iCUE dashboard, 3 × 2 grid)

```
┌───────────────────────────────┬───────────────┐
│  1               2            │  3a  Coords   │
│                               │  (auto, 500ms)│
│      MC Live Map (Large)      ├───────────────┤
│      follows the player       │  3b  Coords   │
│                               │  (tap-to-pin) │
└───────────────────────────────┴───────────────┘
```

- **MC Live Map** (`widgets/map`) — chrome-free map centered on you; auto-switches
  dimension (Nether shows the cave layer at your Y). Zoom + day/night/topo via
  widget settings in iCUE.
- **MC Coordinates** (`widgets/coords`) — X/Y/Z, dimension, facing; updates twice a second.
- **MC Coordinates (tap)** (`widgets/coords-tap`) — updates **only when tapped**;
  shows the capture time. Use it to pin a spot (portal, base, drop chest) while you keep moving.

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

Registers `focus-guard.ps1` as a hidden at-logon task and starts it. When a tap
on the Edge steals focus from Minecraft, it gives focus straight back and snaps
the cursor to where it was — the widget still gets the tap, the game never
minimizes or loses input. Only the ultra-wide (32:9) monitor is guarded;
the other monitors behave normally. Remove with `-Uninstall`.

The borderless fullscreen mod (installed in step 1) keeps the game
full-screen-borderless so even a stolen focus can't minimize it. In Minecraft's
video settings, use its borderless toggle instead of vanilla fullscreen.

### 3. Widgets (one-time, manual in iCUE)

```powershell
.\scripts\package-widgets.ps1
```

Then in **iCUE → Xeneon Edge → Widgets**: import each `dist\*.icuewidget`
(+ button), and arrange the dashboard:

| Slot | Widget | Size |
|------|--------|------|
| columns 1–2 | MC Live Map | Large (2/3 screen) |
| 3a (top right) | MC Coordinates | Small |
| 3b (bottom right) | MC Coordinates (tap) | Small |

iCUE remembers the layout — this is the only manual arrangement step.

### Day-to-day

Nothing. Launch Minecraft (solo or Realms), join a world, and the panels light
up; quit and they show "Minecraft not running". The guard task idles when the
game is closed.

## How it works

- JourneyMap maps client-side, so Realms works; its WebMap addon serves an
  unauthenticated localhost REST API: `/data/player` (position/heading/dimension),
  `/data/all?images.since=` (changed map regions), `/tiles/tile.png` (512px region
  tiles). The map widget bundles Leaflet (`CRS.Simple`, native zoom 0,
  1 block = 1 map unit) and re-fetches only regions JourneyMap re-rendered.
- Each widget folder is self-contained (own copy of `jm-api.js`) because iCUE
  imports widgets as standalone packages. Keep the copies identical.
- The Edge is a real Windows display even in dashboard mode, so touches *do*
  reach Windows — that's why the focus guard exists.

## Troubleshooting

- **Widgets say "Minecraft not running" in-game** — check
  `http://localhost:8080/data/player` in a browser. If the port differs
  (JourneyMap picks a free one if 8080 is busy), either re-run
  `install-mods.ps1` after a launch to pin it, or set the widget's
  "JourneyMap webmap URL" property in iCUE.
- **Map is black in a new area** — JourneyMap only maps where you've been;
  give it a few seconds after entering a world.
- **Tap minimizes the game anyway** — is the focus guard task running?
  `Get-ScheduledTask MinecraftHUD-FocusGuard` should say Running; re-run
  `scripts\install-tasks.ps1`. Also make sure the game uses Borderless
  Fullscreen, not vanilla fullscreen.
- **New Minecraft version, no JourneyMap build yet** — the installer says so
  explicitly. Play the older version until JourneyMap updates (usually days).

## Repo layout

- `widgets/` — the three iCUE widgets (import via `dist/` packages)
- `scripts/` — installer, packager, focus guard, task registration
- `attic/` — retired first iteration: custom Fabric mod (`icuehud`, version-pinned
  HTTP server) + inventory widget that read from it. Superseded by JourneyMap.
