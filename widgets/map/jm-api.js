// Helper for reading the JourneyMap webmap API.
// NOTE: widgets/jm-api.js is the canonical copy. Each widget folder carries
// its own copy because widgets are packaged and imported into iCUE as
// standalone folders. After editing this file run scripts\sync-jm-api.ps1
// (package-widgets.ps1 does it automatically).
var JM = (function () {
	// Standalone/kiosk use: ?apiBase=...&zoomLevel=... stand in for the properties
	// iCUE would inject. Never overrides a value that is already set.
	try {
		new URLSearchParams(window.location.search).forEach(function (value, key) {
			if (window[key] === undefined) window[key] = value;
		});
	} catch (e) {}

	function apiBase() {
		var base = (window.apiBase && window.apiBase.length) ? window.apiBase : "http://localhost:8080";
		return base.replace(/\/+$/, "");
	}

	function facingFromHeading(heading) {
		// Minecraft yaw convention: 0 = south, 90 = west, 180 = north, 270 = east.
		var normalized = ((heading % 360) + 360) % 360;
		var dirs = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"];
		return dirs[Math.round(normalized / 45) % 8];
	}

	var LEGACY_DIMENSIONS = { "0": "minecraft:overworld", "-1": "minecraft:the_nether", "1": "minecraft:the_end" };

	// Normalizes JourneyMap's dimension spellings (0/-1/1 on old builds,
	// "minecraft:overworld", "overworld") to the "minecraft:overworld" form.
	function dimensionKey(dimension) {
		if (dimension === undefined || dimension === null || dimension === "") return "";
		if (typeof dimension === "number") return LEGACY_DIMENSIONS[String(dimension)] || String(dimension);
		var s = String(dimension);
		if (/^-?\d+$/.test(s)) return LEGACY_DIMENSIONS[s] || s;
		return s.indexOf(":") >= 0 ? s : "minecraft:" + s;
	}

	function dimensionLabel(dimension) {
		return dimensionKey(dimension).replace("minecraft:", "");
	}

	function getJson(path) {
		return fetch(apiBase() + path, { cache: "no-store" }).then(function (r) {
			if (!r.ok) throw new Error("HTTP " + r.status);
			return r.json();
		});
	}

	// JourneyMap 6 reports the dimension on /data/world, not /data/player.
	// It changes rarely, so it is cached briefly instead of fetched every poll.
	// options.maxAge (ms, default 2000): 0 forces a fresh request. On failure the
	// cached copy is returned if one is allowed, otherwise the error propagates.
	var worldCache = { at: 0, data: null };
	function fetchWorld(options) {
		var maxAge = (options && typeof options.maxAge === "number") ? options.maxAge : 2000;
		if (worldCache.data && Date.now() - worldCache.at < maxAge) {
			return Promise.resolve(worldCache.data);
		}
		return getJson("/data/world")
			.then(function (world) {
				worldCache = { at: Date.now(), data: world };
				return world;
			})
			.catch(function (err) {
				if (worldCache.data && maxAge > 0) return worldCache.data;
				throw err;
			});
	}

	function fetchPlayer() {
		var world = fetchWorld().catch(function () { return {}; });
		return Promise.all([getJson("/data/player"), world]).then(function (results) {
			var data = results[0];
			var world = results[1];
			if (typeof data.posX !== "number") throw new Error("no player data");
			var dimension = (data.dimension !== undefined) ? data.dimension : world.dimension;
			return {
				x: data.posX,
				y: data.posY,
				z: data.posZ,
				heading: data.heading || 0,
				facing: facingFromHeading(data.heading || 0),
				dimension: dimension,
				dimensionKey: dimensionKey(dimension),
				dimensionLabel: dimensionLabel(dimension),
				biome: data.biome || "",
				underground: !!data.underground,
				sneaking: !!data.sneaking,
				username: data.username || "",
				chunkX: Math.floor(data.posX / 16),
				chunkZ: Math.floor(data.posZ / 16),
				worldName: world.name || "",
				worldTime: (typeof world.time === "number") ? world.time : null,
				raw: data
			};
		});
	}

	function hex2(v) {
		return ("0" + Math.max(0, Math.min(255, Math.round(v))).toString(16)).slice(-2);
	}

	function waypointColor(wp) {
		if (typeof wp.r === "number" && typeof wp.g === "number" && typeof wp.b === "number") {
			return "#" + hex2(wp.r) + hex2(wp.g) + hex2(wp.b);
		}
		var packed = (typeof wp.color === "number") ? wp.color : (typeof wp.colorInt === "number" ? wp.colorInt : null);
		if (packed !== null) return "#" + hex2((packed >> 16) & 255) + hex2((packed >> 8) & 255) + hex2(packed & 255);
		if (typeof wp.color === "string" && wp.color) return wp.color;
		return "#3ea6ff";
	}

	function numberOr(value, fallback) {
		return (typeof value === "number" && isFinite(value)) ? value : fallback;
	}

	function firstDefined() {
		for (var i = 0; i < arguments.length; i++) {
			if (arguments[i] !== undefined && arguments[i] !== null) return arguments[i];
		}
		return undefined;
	}

	// JourneyMap 5 and 6 spell waypoints differently. Verified against 6.0.5:
	// { guid, name, pos: {x,y,z,primaryDimension}, color: <packed ARGB>,
	//   settings: { enable, showOnMap, ... }, icon: { id }, groupId, dimensions: [] }.
	// JourneyMap 5: { id, name, x, y, z, r, g, b, enable, type: "Normal"|"Death", dimensions }.
	function normalizeWaypoint(wp, key) {
		if (!wp || typeof wp !== "object") return null;
		var pos = (wp.pos && typeof wp.pos === "object") ? wp.pos : ((wp.position && typeof wp.position === "object") ? wp.position : wp);
		var x = numberOr(pos.x, null), z = numberOr(pos.z, null);
		if (x === null || z === null) return null;
		var dims = (wp.dimensions !== undefined) ? wp.dimensions : ((wp.dimension !== undefined) ? wp.dimension : wp.dim);
		if (!Array.isArray(dims)) dims = (dims === undefined || dims === null) ? [] : [dims];
		if (!dims.length && pos.primaryDimension) dims = [pos.primaryDimension];
		var settings = (wp.settings && typeof wp.settings === "object") ? wp.settings : {};
		var name = String(wp.name || key || "Waypoint");
		var type = String(wp.type || (wp.deathPoint ? "Death" : "Normal"));
		var iconId = (wp.icon && typeof wp.icon === "object") ? String(wp.icon.id || "") : String(wp.icon || "");
		return {
			id: String(firstDefined(wp.id, wp.guid, key, name)),
			name: name,
			x: x,
			y: numberOr(pos.y, 64),
			z: z,
			color: waypointColor(wp),
			type: type,
			isDeath: /death/i.test(type) || wp.deathPoint === true
				|| /death/i.test(String(wp.groupId || "")) || /death/i.test(iconId) || /^death\b/i.test(name),
			enabled: !!firstDefined(wp.enable, wp.enabled, settings.enable, true),
			showOnMap: !!firstDefined(settings.showOnMap, wp.showOnMap, true),
			dimensions: dims.map(dimensionKey),
			raw: wp
		};
	}

	// Resolves to a normalized array of waypoints (see normalizeWaypoint).
	function fetchWaypoints() {
		return getJson("/data/waypoints").then(function (data) {
			if (data && !Array.isArray(data) && data.waypoints && typeof data.waypoints === "object") data = data.waypoints;
			var list = [];
			if (Array.isArray(data)) {
				data.forEach(function (wp, i) { var n = normalizeWaypoint(wp, String(i)); if (n) list.push(n); });
			} else if (data && typeof data === "object") {
				Object.keys(data).forEach(function (key) { var n = normalizeWaypoint(data[key], key); if (n) list.push(n); });
			}
			return list;
		});
	}

	function distance(ax, ay, az, bx, by, bz) {
		var dx = bx - ax, dy = by - ay, dz = bz - az;
		return Math.sqrt(dx * dx + dy * dy + dz * dz);
	}

	// Yaw (Minecraft convention) of the direction from (fromX, fromZ) to (toX, toZ).
	function bearingTo(fromX, fromZ, toX, toZ) {
		var yaw = Math.atan2(-(toX - fromX), toZ - fromZ) * 180 / Math.PI;
		return ((yaw % 360) + 360) % 360;
	}

	// How far to turn from `heading` to face `targetYaw`: -180..180, positive = clockwise (to the right).
	function relativeBearing(heading, targetYaw) {
		var d = (((targetYaw - heading) % 360) + 360) % 360;
		return d > 180 ? d - 360 : d;
	}

	return {
		apiBase: apiBase,
		getJson: getJson,
		fetchPlayer: fetchPlayer,
		fetchWorld: fetchWorld,
		fetchWaypoints: fetchWaypoints,
		facingFromHeading: facingFromHeading,
		dimensionKey: dimensionKey,
		dimensionLabel: dimensionLabel,
		distance: distance,
		bearingTo: bearingTo,
		relativeBearing: relativeBearing
	};
})();
