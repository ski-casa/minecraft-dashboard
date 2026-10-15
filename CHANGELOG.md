# Changelog

Versions follow [semantic versioning](https://semver.org): the number in
`VERSION` is the project's; the bridge mod jar and the widget packages carry
the same number.

## 1.0.0 — 2026-10-15

First release. The project started as a HUD for the Corsair Xeneon Edge and
now works on any second monitor.

- **Dashboard**: kiosk page with an on-screen layout editor (drag, resize,
  add, per-widget settings), grid-based so one layout fits any screen; named
  layouts saved per monitor; move between monitors from the Screen menu;
  `config.js` as the starting layout with two samples.
- **Widgets** (20): live map (with trail and base-cam modes), coordinates,
  coordinates (tap), waypoints, threats, armor durability, materials,
  inventory, XP, flight, day/night clock, environment, effects, death
  recovery, light & spawn risk, day counter, connection, quick actions,
  timers, checklist; plus web page and empty panels.
- **Bridge mod** (Fabric, client-side): serves inventory, equipment, effects,
  vitals, light, weather, time, last death, ping/FPS and tracked chests on
  `localhost:27421`; `POST /action` for key presses, chat, capture and
  screenshots; in-game keys for chest tracking and position capture.
- **Setup**: `scripts\setup.ps1` installs Java, Fabric, Fabric API,
  JourneyMap (+ WebMap), a borderless-fullscreen mod and the bridge mod, pins
  versions, and opens the dashboard; re-runnable after game updates.
- **Touchscreen**: focus guard so taps never steal input from the game;
  iCUE widget packaging for the Xeneon Edge.
