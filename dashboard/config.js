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
	watchConfig: true,                    // re-read this file every few seconds and apply changes

	panels: [
		// LEFT WIDGETS
		{ widget: "clock", col: 1, row: 1, colSpan: 3, rowSpan: 3, params: { hourFormat: 24 } },
		{ widget: "coords", col: 1, row: 4, colSpan: 3, rowSpan: 3 },
		{ widget: "coords-tap", col: 1, row: 7, colSpan: 3, rowSpan: 3 },

		// CENTER MAP
		{ widget: "map", col: 4, row: 1, colSpan: 10, rowSpan: 9, params: { zoomLevel: 2, mapMode: "auto" } },

		// RIGHT WIDGETS
		{ widget: "waypoints", col: 14, row: 1, colSpan: 3, rowSpan: 5 },
		{ widget: "environment", col: 14, row: 6, colSpan: 3, rowSpan: 4 }
	]
};
