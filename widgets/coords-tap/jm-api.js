// Helper for reading the JourneyMap webmap API.
// NOTE: each widget folder carries its own copy of this file, because widgets
// are packaged and imported into iCUE as standalone folders. Keep the copies
// in widgets/*/jm-api.js identical.
var JM = (function () {
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

	function dimensionLabel(dimension) {
		// JourneyMap reports "minecraft:overworld" (modern) or 0/-1/1 (legacy builds).
		if (typeof dimension === "number") {
			return { "0": "overworld", "-1": "the_nether", "1": "the_end" }[String(dimension)] || String(dimension);
		}
		return String(dimension || "").replace("minecraft:", "");
	}

	function fetchPlayer() {
		return fetch(apiBase() + "/data/player", { cache: "no-store" })
			.then(function (r) {
				if (!r.ok) throw new Error("HTTP " + r.status);
				return r.json();
			})
			.then(function (data) {
				if (typeof data.posX !== "number") throw new Error("no player data");
				return {
					x: data.posX,
					y: data.posY,
					z: data.posZ,
					heading: data.heading || 0,
					facing: facingFromHeading(data.heading || 0),
					dimension: data.dimension,
					dimensionLabel: dimensionLabel(data.dimension),
					biome: data.biome || "",
					raw: data
				};
			});
	}

	return {
		apiBase: apiBase,
		fetchPlayer: fetchPlayer,
		facingFromHeading: facingFromHeading,
		dimensionLabel: dimensionLabel
	};
})();
