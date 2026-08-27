// Minimal stand-in for the JourneyMap webmap API, for testing the widgets
// without launching Minecraft:  node tools/mock-jm-server.mjs [port]
// Then open widgets/*/index.html in a browser with the widget's apiBase
// pointing at http://localhost:<port> (default 8080).
import http from "node:http";
import zlib from "node:zlib";

const port = Number(process.argv[2] || 8080);
const start = Date.now();

// The "player" walks a circle so movement/facing/centering are visible.
function player() {
	const t = (Date.now() - start) / 1000;
	return {
		posX: Math.round(Math.cos(t / 10) * 300 * 100) / 100,
		posY: 64,
		posZ: Math.round(Math.sin(t / 10) * 300 * 100) / 100,
		heading: Math.round((t * 6) % 360),
		dimension: "minecraft:overworld",
		biome: "Plains",
		username: "mock",
		entityId: "00000000-0000-0000-0000-000000000000"
	};
}

// Tiny PNG encoder: one 512x512 checkerboard tile, generated once.
function makeTilePng() {
	const size = 512, cell = 64;
	const raw = Buffer.alloc(size * (1 + size * 3));
	for (let y = 0; y < size; y++) {
		const row = y * (1 + size * 3);
		raw[row] = 0; // filter: none
		for (let x = 0; x < size; x++) {
			const dark = ((x / cell | 0) + (y / cell | 0)) % 2 === 0;
			const o = row + 1 + x * 3;
			raw[o] = dark ? 0x2e : 0x4c;
			raw[o + 1] = dark ? 0x57 : 0x7a;
			raw[o + 2] = dark ? 0x2e : 0x4c;
		}
	}
	const crcTable = [...Array(256)].map((_, n) => {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		return c >>> 0;
	});
	const crc = (buf) => {
		let c = 0xffffffff;
		for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
		return (c ^ 0xffffffff) >>> 0;
	};
	const chunk = (type, data) => {
		const len = Buffer.alloc(4);
		len.writeUInt32BE(data.length);
		const body = Buffer.concat([Buffer.from(type), data]);
		const sum = Buffer.alloc(4);
		sum.writeUInt32BE(crc(body));
		return Buffer.concat([len, body, sum]);
	};
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(size, 0);
	ihdr.writeUInt32BE(size, 4);
	ihdr[8] = 8;  // bit depth
	ihdr[9] = 2;  // color type: RGB
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk("IHDR", ihdr),
		chunk("IDAT", zlib.deflateSync(raw)),
		chunk("IEND", Buffer.alloc(0))
	]);
}
const tilePng = makeTilePng();

http.createServer((req, res) => {
	const url = new URL(req.url, "http://localhost");
	res.setHeader("Access-Control-Allow-Origin", "*");
	if (url.pathname === "/data/player") {
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify(player()));
	} else if (url.pathname === "/data/all") {
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify({
			player: player(),
			world: { dimension: "minecraft:overworld", time: 1000 },
			images: { since: Date.now(), regions: [] }
		}));
	} else if (url.pathname === "/tiles/tile.png") {
		res.setHeader("Content-Type", "image/png");
		res.end(tilePng);
	} else if (url.pathname === "/status") {
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify({ status: "ready" }));
	} else {
		res.statusCode = 404;
		res.end("not found");
	}
}).listen(port, "127.0.0.1", () => {
	console.log(`mock JourneyMap webmap on http://localhost:${port}`);
});
