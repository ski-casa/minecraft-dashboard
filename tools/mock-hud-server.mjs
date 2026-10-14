// Minimal stand-in for the iCUE HUD Bridge mod (mod/), for testing the armor
// and materials widgets without launching Minecraft:  node tools/mock-hud-server.mjs [port]
// Then open the dashboard (modApiBase http://localhost:<port>, default 27421).
// Armor wears down over time, a chest is opened/closed every so often.
import http from "node:http";

const port = Number(process.argv[2] || 27421);
const start = Date.now();
let lastAction = null;   // the last /action body, echoed in /state for tests

function gear(id, name, maxDamage, wearPerSecond, offset) {
	const t = (Date.now() - start) / 1000;
	const damage = Math.min(maxDamage - 1, Math.floor(offset + t * wearPerSecond));
	return { id, name, count: 1, maxCount: 1, damage, maxDamage };
}

function state() {
	const t = (Date.now() - start) / 1000;
	const chestOpen = Math.floor(t / 10) % 3 === 1;      // open for 10 s out of every 30
	const stoneInInv = 64 * 4 + Math.floor(t) % 64;
	return {
		inGame: true,
		world: "sp_mock",
		// effects count down and come back; a death 90 s ago, 120 blocks north-east
		effects: [
			{ id: "minecraft:fire_resistance", name: "Fire Resistance", duration: Math.max(0, 1800 - Math.floor(t * 20) % 2400), amplifier: 0, category: "beneficial", color: 0xff9900, ambient: false },
			{ id: "minecraft:speed", name: "Speed", duration: 6000 - Math.floor(t * 20) % 6000, amplifier: 1, category: "beneficial", color: 0x33ebff, ambient: false },
			{ id: "minecraft:poison", name: "Poison", duration: Math.floor(t) % 40 < 20 ? 400 - (Math.floor(t * 20) % 400) : 0, amplifier: 0, category: "harmful", color: 0x87a363, ambient: false },
			{ id: "minecraft:haste", name: "Haste", duration: -1, amplifier: 1, category: "beneficial", color: 0xd9c043, ambient: true }
		].filter(e => e.duration !== 0),
		death: { at: start - 90000, x: 85, y: 40, z: -85, dimension: "minecraft:overworld" },
		vitals: { health: 14, maxHealth: 20, absorption: 0, food: 11, saturation: 2.5, air: 300, maxAir: 300, armor: 15, xpLevel: 27, xpProgress: 0.6, onFire: false, inWater: false },
		environment: { blockLight: 3, skyLight: 15, raining: false, thundering: false, dayTime: Math.floor(t * 20) % 24000, gameTime: Math.floor(t * 20), moonPhase: 2, fps: 118, ping: 42, sessionStart: start },
		lastAction: lastAction,
		dimension: "minecraft:overworld",
		player: { x: 0, y: 64, z: 0 },
		inventory: [
			{ slot: 0, id: "minecraft:smooth_stone", name: "Smooth Stone", count: stoneInInv, maxCount: 64 },
			{ slot: 1, id: "minecraft:white_stained_glass", name: "White Stained Glass", count: 30, maxCount: 64 }
		],
		equipment: {
			head: gear("minecraft:diamond_helmet", "Diamond Helmet", 363, 0.5, 0),
			chest: gear("minecraft:netherite_chestplate", "Netherite Chestplate", 592, 2, 250),
			legs: null,
			feet: gear("minecraft:iron_boots", "Iron Boots", 195, 1, 150),
			mainhand: gear("minecraft:diamond_pickaxe", "Diamond Pickaxe", 1561, 3, 0),
			offhand: { id: "minecraft:totem_of_undying", name: "Totem of Undying", count: 1, maxCount: 1 }
		},
		containers: [
			{ key: "minecraft:overworld|10,64,10", known: true, tracked: true, dimension: "minecraft:overworld", x: 10, y: 64, z: 10, type: "chest", seenAt: start,
				items: [{ id: "minecraft:smooth_stone", count: 640 }, { id: "minecraft:white_stained_glass", count: 200 }] },
			{ key: "minecraft:overworld|12,64,10", known: true, tracked: true, dimension: "minecraft:overworld", x: 12, y: 64, z: 10, type: "barrel", seenAt: start,
				items: [{ id: "minecraft:smooth_stone", count: 128 }] }
		],
		openContainer: chestOpen ? { key: "minecraft:overworld|-5,64,3", known: true, tracked: false, dimension: "minecraft:overworld", x: -5, y: 64, z: 3, type: "chest", seenAt: Date.now(), items: [] } : null,
		totals: {
			"minecraft:smooth_stone": { inventory: stoneInInv, containers: 768 },
			"minecraft:white_stained_glass": { inventory: 30, containers: 200 }
		}
	};
}

http.createServer((req, res) => {
	const url = new URL(req.url, "http://localhost");
	res.setHeader("Access-Control-Allow-Origin", "*");
	if (url.pathname === "/state") {
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify(state()));
	} else if (url.pathname === "/action") {
		res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
		res.setHeader("Access-Control-Allow-Headers", "Content-Type");
		if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return; }
		let body = "";
		req.on("data", c => body += c);
		req.on("end", () => {
			try { lastAction = JSON.parse(body); lastAction.at = Date.now(); console.log("action:", body); res.setHeader("Content-Type", "application/json"); res.end('{"ok":true}'); }
			catch (e) { res.statusCode = 400; res.end('{"ok":false,"error":"bad json"}'); }
		});
	} else if (url.pathname === "/icon") {
		res.statusCode = 404;      // the widgets fall back to a glyph / initial
		res.end("no icons in the mock");
	} else {
		res.statusCode = 404;
		res.end("mock icuehud: /state or /icon?id=");
	}
}).listen(port, "127.0.0.1", () => {
	console.log(`mock icuehud server on http://localhost:${port}/state`);
});
