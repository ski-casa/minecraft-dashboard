// Minecraft HUD dashboard layout.
//
// Edit and save: the running dashboard picks up changes within a few seconds
// (no restart needed). Mistakes are reported in a red banner on the screen.
// Full reference, widget list and examples: dashboard/README.md
//
// The screen is divided into grid.columns x grid.rows equal cells. Each panel
// names a widget (a folder under widgets/) and the cell it starts at (col/row,
// counted from 1) plus how many cells it spans.

window.HUD_CONFIG = {
	grid: { columns: 16, rows: 9 },       // 2560x720 -> ~151x71 cells; a 3x3 span is ~470x229, the 10x9 map ~1547x704
	gap: 8,                               // space between panels (px)
	padding: 8,                           // space around the whole grid (px)
	radius: 10,                           // panel corner radius (px)
	background: "#000",                   // screen background
	panelBackground: "#101014",           // panel background (also shown while a widget loads)
	apiBase: "http://localhost:8080",     // JourneyMap webmap URL, passed to every widget
	modApiBase: "http://localhost:27421", // iCUE HUD Bridge mod URL (armor + materials widgets)
	watchConfig: true,                    // re-read this file every few seconds and apply changes

	panels: [
		// LEFT WIDGETS
		{ widget: "clock", col: 1, row: 1, colSpan: 2, rowSpan: 3, params: { hourFormat: 24 } },
		{ widget: "coords", col: 1, row: 4, colSpan: 2, rowSpan: 3 },
		{ widget: "coords-tap", col: 1, row: 7, colSpan: 2, rowSpan: 3 },

		// CENTER MAP
		{ widget: "map", col: 3, row: 1, colSpan: 8, rowSpan: 9, params: {
			zoomLevel: -2
			 ,        // starting zoom: -2 (far) ... 5 (close)
			zoomButtons: true,   // on-screen + / - buttons (pinch also zooms)
			zoomReset: 0,        // seconds after a manual zoom before it returns to zoomLevel (0 = never)
			mapMode: "auto",     // "auto", "day", "night" or "topo"
			autoNight: true,     // auto mode: switch to the night layer after dark
			autoCaves: true,     // auto mode: switch to the cave layer when underground
			mobs: true,          // hostile mobs
			animals: false,      // passive animals
			villagers: true,     // villagers
			players: true,       // other players (you are always the blue arrow)
			waypoints: true,     // your JourneyMap waypoints
			labels: "all"        // name labels: "all", "players", "waypoints" or "none"
		} },

		// GEAR + BUILD PROJECT (need the iCUE HUD Bridge mod: scripts\build-mod.ps1)
		{ widget: "armor", col: 11, row: 1, colSpan: 3, rowSpan: 4, params: {
			slots: "head,chest,legs,feet,offhand",   // also: mainhand (the tool you hold)
			showNames: true
		} },
		{ widget: "materials", col: 11, row: 5, colSpan: 3, rowSpan: 5, params: {
			// "item:amount, item:amount, ..."
			items: "stone:1242, \
			        cobbled_deepslate:254, \
			        cobbled_deepslate_stairs:254, \
			        white_stained_glass:418, \
			        iron:200, \
					diamond:40",
			title: "Materials",
			hideDone: false,     // hide items once you have enough
			sort: "list"         // "list" (as written) or "remaining" (most missing first)
		} },

		// RIGHT WIDGETS
		{ widget: "waypoints", col: 14, row: 1, colSpan: 3, rowSpan: 3 },
		{ widget: "environment", col: 14, row: 6, colSpan: 3, rowSpan: 3 }
	]
};
