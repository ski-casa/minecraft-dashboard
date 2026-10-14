// Widget catalog for the dashboard's layout editor (dashboard/index.html).
//
// The editor cannot list the widgets/ folder itself (the page is opened from
// file://), so every widget that should appear in the "Add widget" menu is
// described here: a name, what it does, a sensible starting size in grid
// cells, and its settings. Each setting becomes a field in the panel's
// settings dialog and is passed to the widget as ?name=value, exactly like
// `params` in config.js.
//
// Every entry has a category (see HUD_CATEGORIES below) so the Add menu stays
// browsable as the list grows.
//
// Setting types: "text", "number" (with optional min/max/step), "bool",
// "select" (with options: ["a", "b"] or [{ value: "a", label: "A" }]).
// A value equal to its default is not stored, so exported layouts stay short.
//
// Adding your own widget: make widgets/<name>/index.html (see README.md,
// "Adding your own widget") and add an entry below.

window.HUD_CATEGORIES = [
	{ id: "map", name: "Map & navigation", description: "where you are and where things are" },
	{ id: "inventory", name: "Inventory & gear", description: "what you carry, wear and have stored" },
	{ id: "status", name: "Status", description: "time, world, player condition" },
	{ id: "tools", name: "Tools", description: "touch-driven helpers" }
];

window.HUD_WIDGETS = [
	{
		id: "map",
		category: "map",
		name: "Live map",
		description: "JourneyMap centered on you, with mobs, villagers, players and waypoints drawn on top.",
		size: { colSpan: 8, rowSpan: 9 },
		params: [
			{ name: "zoomLevel", label: "Starting zoom", type: "number", min: -2, max: 5, step: 1, default: 2, help: "-2 (far) … 5 (close)" },
			{ name: "zoomButtons", label: "Zoom buttons", type: "bool", default: true, help: "+ / − in the bottom-right corner" },
			{ name: "zoomReset", label: "Return to starting zoom after", type: "number", min: 0, step: 5, default: 0, help: "seconds; 0 = never" },
			{ name: "mapMode", label: "Map layer", type: "select", options: ["auto", "day", "night", "topo"], default: "auto" },
			{ name: "autoNight", label: "Auto: night layer after dark", type: "bool", default: true },
			{ name: "autoCaves", label: "Auto: cave layer underground", type: "bool", default: true },
			{ name: "mobs", label: "Hostile mobs", type: "bool", default: true },
			{ name: "animals", label: "Animals", type: "bool", default: true },
			{ name: "villagers", label: "Villagers", type: "bool", default: true },
			{ name: "players", label: "Other players", type: "bool", default: true },
			{ name: "waypoints", label: "Waypoints", type: "bool", default: true },
			{ name: "labels", label: "Name labels", type: "select", options: ["all", "players", "waypoints", "none"], default: "all" },
			{ name: "trail", label: "Trail (minutes of your path)", type: "number", min: 0, max: 120, step: 1, default: 0, help: "0 = off; draws where you walked" },
			{ name: "centerX", label: "Fixed center X", type: "text", default: "", help: "blank = follow you; with Z, the map watches a place (base cam)" },
			{ name: "centerZ", label: "Fixed center Z", type: "text", default: "" }
		]
	},
	{
		id: "coords",
		category: "map",
		name: "Coordinates",
		description: "X / Y / Z, dimension and facing, live.",
		size: { colSpan: 2, rowSpan: 3 },
		params: []
	},
	{
		id: "coords-tap",
		category: "map",
		name: "Coordinates (tap)",
		description: "Stores your position when tapped (or with the H key in game) so you can pin a spot and keep moving.",
		size: { colSpan: 2, rowSpan: 3 },
		params: [
			{ name: "hotkey", label: "Capture with the in-game key", type: "bool", default: true, help: "needs the iCUE HUD Bridge mod" }
		]
	},
	{
		id: "clock",
		category: "status",
		name: "Day / night clock",
		description: "In-game time on a sun/moon arc, countdown to nightfall or dawn, and when the bed works.",
		size: { colSpan: 2, rowSpan: 3 },
		params: [
			{ name: "hourFormat", label: "Clock format", type: "select", options: [{ value: 24, label: "24-hour" }, { value: 12, label: "12-hour" }], default: 24 }
		]
	},
	{
		id: "waypoints",
		category: "map",
		name: "Waypoints",
		description: "Your JourneyMap waypoints by distance, with an arrow relative to where you face. Tap a row to pin it.",
		size: { colSpan: 3, rowSpan: 4 },
		params: [
			{ name: "dimensions", label: "Show waypoints from", type: "select", options: [{ value: "current", label: "this dimension" }, { value: "all", label: "all dimensions" }], default: "current" },
			{ name: "maxRows", label: "Rows", type: "number", min: 1, max: 50, step: 1, default: 12 },
			{ name: "deathFirst", label: "Death points first", type: "bool", default: true }
		]
	},
	{
		id: "environment",
		category: "status",
		name: "Environment",
		description: "Biome, the portal-linked coordinates for where you stand, chunk and region.",
		size: { colSpan: 3, rowSpan: 4 },
		params: []
	},
	{
		id: "armor",
		category: "inventory",
		name: "Armor durability",
		description: "Durability bars for helmet, chestplate, leggings, boots and off hand. Needs the iCUE HUD Bridge mod.",
		size: { colSpan: 3, rowSpan: 4 },
		params: [
			{ name: "slots", label: "Slots, in order", type: "text", default: "head,chest,legs,feet", help: "from head, chest, legs, feet, mainhand, offhand" },
			{ name: "showNames", label: "Item names", type: "bool", default: true },
			{ name: "title", label: "Title", type: "text", default: "Durability", help: "blank for none" }
		]
	},
	{
		id: "materials",
		category: "inventory",
		name: "Materials",
		description: "A build's shopping list with have/need per item, counting your inventory and tracked chests. Needs the mod.",
		size: { colSpan: 3, rowSpan: 5 },
		params: [
			{ name: "items", label: "Items", type: "text", default: "", multiline: true, help: "name:amount, name:amount … e.g. smooth_stone:1242, white_stained_glass:418" },
			{ name: "title", label: "Title", type: "text", default: "Materials", help: "blank for none" },
			{ name: "hideDone", label: "Hide finished items", type: "bool", default: false },
			{ name: "sort", label: "Order", type: "select", options: [{ value: "list", label: "as written" }, { value: "remaining", label: "most missing first" }], default: "list" }
		]
	},
	{
		id: "threats",
		name: "Threats",
		description: "Hostile mobs from JourneyMap's radar as a list: what, how far, which way. Creeper behind you at 6 blocks.",
		category: "map",
		size: { colSpan: 3, rowSpan: 4 },
		params: [
			{ name: "maxRows", label: "Rows", type: "number", min: 1, max: 30, step: 1, default: 8 },
			{ name: "range", label: "Only within (blocks)", type: "number", min: 0, max: 256, step: 8, default: 0, help: "0 = everything the radar sees" }
		]
	},
	{
		id: "effects",
		name: "Effects",
		description: "Potion effects with countdown bars; warns before Fire Resistance, Water Breathing or Slow Falling run out. Needs the mod.",
		category: "status",
		size: { colSpan: 3, rowSpan: 4 },
		params: [
			{ name: "title", label: "Title", type: "text", default: "Effects", help: "blank for none" },
			{ name: "warnSeconds", label: "Warn in the last (seconds)", type: "number", min: 5, max: 300, step: 5, default: 30 },
			{ name: "showVitals", label: "Health / food / air row", type: "bool", default: true }
		]
	},
	{
		id: "death",
		name: "Death recovery",
		description: "Where you last died: distance, direction and a countdown until the dropped items despawn. Needs the mod.",
		category: "status",
		size: { colSpan: 3, rowSpan: 3 },
		params: [
			{ name: "despawnMinutes", label: "Items despawn after (minutes)", type: "number", min: 1, max: 30, step: 1, default: 5 },
			{ name: "hideAfterMinutes", label: "Hide after (minutes)", type: "number", min: 0, max: 1440, step: 10, default: 60, help: "0 = keep showing the last death" }
		]
	},
	{
		id: "light",
		name: "Light & spawn risk",
		description: "Block and sky light where you stand, whether mobs can spawn there, weather and moon phase. Needs the mod.",
		category: "status",
		size: { colSpan: 3, rowSpan: 3 },
		params: []
	},
	{
		id: "daycounter",
		name: "Day counter",
		description: "World day number, time played this session and the real clock. Needs the mod.",
		category: "status",
		size: { colSpan: 2, rowSpan: 2 },
		params: [
			{ name: "hourFormat", label: "Real clock format", type: "select", options: [{ value: 24, label: "24-hour" }, { value: 12, label: "12-hour" }], default: 24 }
		]
	},
	{
		id: "inventory",
		name: "Inventory",
		description: "Your 36 slots as a grid with counts, and how many are free. Needs the mod.",
		category: "inventory",
		size: { colSpan: 4, rowSpan: 4 },
		params: [
			{ name: "hotbar", label: "Hotbar row", type: "select", options: [{ value: "bottom", label: "at the bottom (like the game)" }, { value: "top", label: "at the top" }, { value: "hide", label: "hidden" }], default: "bottom" }
		]
	},
	{
		id: "xp",
		name: "XP & enchanting",
		description: "Level, progress to the next, lapis on hand and a highlight once the target level is reached. Needs the mod.",
		category: "inventory",
		size: { colSpan: 2, rowSpan: 2 },
		params: [
			{ name: "target", label: "Target level", type: "number", min: 1, max: 100, step: 1, default: 30 }
		]
	},
	{
		id: "flight",
		name: "Flight",
		description: "Elytra durability, rockets, altitude, speed and heading while gliding. Needs the mod.",
		category: "inventory",
		size: { colSpan: 3, rowSpan: 3 },
		params: []
	},
	{
		id: "connection",
		name: "Connection",
		description: "Ping to the server or Realm and client FPS. Needs the mod.",
		category: "status",
		size: { colSpan: 2, rowSpan: 2 },
		params: []
	},
	{
		id: "actions",
		name: "Quick actions",
		description: "Big buttons that act in game: press a key (JourneyMap's B to mark a waypoint), send a chat line, capture coordinates, screenshot. Needs the mod.",
		category: "tools",
		size: { colSpan: 3, rowSpan: 3 },
		params: [
			{ name: "buttons", label: "Buttons", type: "text", multiline: true, default: "Mark here|key:B; Capture|capture; Screenshot|screenshot; View|perspective; Heading home|chat:heading home", help: "Label|action:text; ... actions: key:<KEY>, chat:<text>, command:<cmd>, capture, perspective, screenshot, message:<text>" },
			{ name: "columns", label: "Columns", type: "number", min: 0, max: 6, step: 1, default: 0, help: "0 = automatic" },
			{ name: "title", label: "Title", type: "text", default: "" }
		]
	},
	{
		id: "timers",
		name: "Timers",
		description: "Tap-to-start countdowns and a stopwatch: smelting batches, brewing, crops. No mod needed.",
		category: "tools",
		size: { colSpan: 3, rowSpan: 3 },
		params: [
			{ name: "presets", label: "Timers", type: "text", multiline: true, default: "Furnace x64|10:40; Brewing|0:20; Stopwatch|0", help: "Name|m:ss; ... (0 = stopwatch)" }
		]
	},
	{
		id: "checklist",
		name: "Checklist",
		description: "Steps to tick off: a build plan, an expedition packing list. Ticks are remembered. No mod needed.",
		category: "tools",
		size: { colSpan: 3, rowSpan: 4 },
		params: [
			{ name: "title", label: "Title", type: "text", default: "Checklist" },
			{ name: "items", label: "Items", type: "text", multiline: true, default: "Pack food; Torches; Water bucket; Bed", help: "separated by ;" }
		]
	}
];

// Settings every widget understands, shown below the widget's own.
window.HUD_COMMON_PARAMS = [
	{ name: "fontScale", label: "Text size", type: "number", min: 0.3, max: 4, step: 0.1, default: 1, help: "1 = normal; 1.3 is 30 % larger" }
];
