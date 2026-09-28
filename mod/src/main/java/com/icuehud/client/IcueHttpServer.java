package com.icuehud.client;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.Identifier;
import net.minecraft.server.packs.resources.Resource;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;

/**
 * Loopback-only HTTP API:
 *   GET /state           the current snapshot (see IcueHudClient.onTick)
 *   GET /icon?id=<item>  the item's texture as PNG (falls back to its block texture), 404 if none
 */
public class IcueHttpServer {
	private static final byte[] NO_ICON = new byte[0];

	private final GameState state;
	private final int port;
	private final Map<String, byte[]> iconCache = new ConcurrentHashMap<>();
	private HttpServer server;

	public IcueHttpServer(GameState state, int port) {
		this.state = state;
		this.port = port;
	}

	public void start() {
		try {
			server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
			server.createContext("/state", this::handleState);
			server.createContext("/icon", this::handleIcon);
			server.createContext("/", ex -> send(ex, 404, "text/plain", "icuehud: try /state or /icon?id=minecraft:stone".getBytes(StandardCharsets.UTF_8)));
			server.setExecutor(Executors.newFixedThreadPool(2, r -> {
				Thread t = new Thread(r, "icuehud-http");
				t.setDaemon(true);
				return t;
			}));
			server.start();
			System.out.println(IcueHudClient.LOG_PREFIX + "HTTP server listening on 127.0.0.1:" + port);
		} catch (IOException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "failed to start HTTP server on port " + port + ": " + e.getMessage());
		}
	}

	public void stop() {
		if (server != null) server.stop(0);
	}

	private void handleState(HttpExchange exchange) throws IOException {
		send(exchange, 200, "application/json; charset=utf-8", state.get().getBytes(StandardCharsets.UTF_8));
	}

	private void handleIcon(HttpExchange exchange) throws IOException {
		String query = exchange.getRequestURI().getRawQuery();
		String id = null;
		if (query != null) {
			for (String part : query.split("&")) {
				if (part.startsWith("id=")) id = URLDecoder.decode(part.substring(3), StandardCharsets.UTF_8);
			}
		}
		Identifier item = id == null ? null : Identifier.tryParse(id.contains(":") ? id : "minecraft:" + id);
		if (item == null) {
			send(exchange, 400, "text/plain", "missing or invalid id".getBytes(StandardCharsets.UTF_8));
			return;
		}
		byte[] png = iconCache.computeIfAbsent(item.toString(), k -> loadIcon(item));
		if (png == NO_ICON) {
			send(exchange, 404, "text/plain", "no flat texture for this item".getBytes(StandardCharsets.UTF_8));
		} else {
			exchange.getResponseHeaders().set("Cache-Control", "max-age=86400");
			send(exchange, 200, "image/png", png);
		}
	}

	// Shapes that only exist as 3D models; their icon is the material they are made of.
	private static final String[] SHAPE_SUFFIXES = {
			"_stairs", "_slab", "_wall", "_fence_gate", "_fence", "_button", "_pressure_plate", "_trapdoor", "_pane"
	};

	/**
	 * Icon lookup, in order: the item's own flat sprite from the game files; the
	 * Minecraft Wiki's inventory sprite (a proper render for 3D blocks such as
	 * stairs and chests, fetched once and cached under config/icuehud/icons);
	 * the block's face; the face of the material a stair/slab/wall is cut from.
	 */
	private static byte[] loadIcon(Identifier item) {
		String ns = item.getNamespace(), name = item.getPath();
		byte[] own = readResource(ns, "textures/item/" + name + ".png");
		if (own != null) return own;
		byte[] wiki = wikiSprite(item);
		if (wiki != null) return wiki;

		java.util.List<String> candidates = new java.util.ArrayList<>();
		addBlockFaces(candidates, name);
		for (String suffix : SHAPE_SUFFIXES) {
			if (!name.endsWith(suffix)) continue;
			String base = name.substring(0, name.length() - suffix.length());
			// cobbled_deepslate_stairs -> cobbled_deepslate; stone_brick_stairs -> stone_bricks;
			// oak_stairs -> oak_planks; quartz_stairs -> quartz_block(_side)
			for (String material : new String[] { base, base + "s", base + "_planks", base + "_block" }) {
				candidates.add("textures/item/" + material + ".png");
				addBlockFaces(candidates, material);
			}
			break;
		}
		for (String path : candidates) {
			byte[] png = readResource(ns, path);
			if (png != null) return png;
		}
		return NO_ICON;
	}

	private static byte[] readResource(String ns, String path) {
		Optional<Resource> res = Minecraft.getInstance().getResourceManager().getResource(Identifier.fromNamespaceAndPath(ns, path));
		if (res.isEmpty()) return null;
		try (InputStream in = res.get().open()) {
			return in.readAllBytes();
		} catch (IOException e) {
			return null;
		}
	}

	// ---- Minecraft Wiki inventory sprites ("Invicon_Cobbled_Deepslate_Stairs.png") ----
	private static final java.nio.file.Path WIKI_CACHE =
			net.fabricmc.loader.api.FabricLoader.getInstance().getConfigDir().resolve("icuehud").resolve("icons");
	private static final java.net.http.HttpClient HTTP = java.net.http.HttpClient.newBuilder()
			.connectTimeout(java.time.Duration.ofSeconds(4)).followRedirects(java.net.http.HttpClient.Redirect.NORMAL).build();

	/** Cached on disk after the first fetch; null when the wiki has no such file or is unreachable. */
	private static byte[] wikiSprite(Identifier item) {
		if (!item.getNamespace().equals("minecraft")) return null;   // the wiki only covers vanilla
		java.nio.file.Path cached = WIKI_CACHE.resolve(item.getPath() + ".png");
		try {
			if (java.nio.file.Files.exists(cached)) return java.nio.file.Files.readAllBytes(cached);
		} catch (IOException e) {
			// fall through to a fresh fetch
		}
		// cobbled_deepslate_stairs -> Cobbled_Deepslate_Stairs
		StringBuilder title = new StringBuilder();
		for (String word : item.getPath().split("_")) {
			if (title.length() > 0) title.append('_');
			title.append(Character.toUpperCase(word.charAt(0))).append(word.substring(1));
		}
		try {
			java.net.http.HttpRequest req = java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://minecraft.wiki/images/Invicon_" + title + ".png"))
					.timeout(java.time.Duration.ofSeconds(6))
					.header("User-Agent", "icuehud/0.2 (Xeneon Edge Minecraft dashboard; caches sprites locally)")
					.GET().build();
			java.net.http.HttpResponse<byte[]> res = HTTP.send(req, java.net.http.HttpResponse.BodyHandlers.ofByteArray());
			String type = res.headers().firstValue("content-type").orElse("");
			if (res.statusCode() != 200 || !type.startsWith("image/")) return null;
			java.nio.file.Files.createDirectories(WIKI_CACHE);
			java.nio.file.Files.write(cached, res.body());
			return res.body();
		} catch (IOException | InterruptedException | RuntimeException e) {
			System.out.println(IcueHudClient.LOG_PREFIX + "no wiki sprite for " + item + " (" + e.getClass().getSimpleName() + ")");
			return null;
		}
	}

	private static void addBlockFaces(java.util.List<String> into, String name) {
		into.add("textures/block/" + name + ".png");
		into.add("textures/block/" + name + "_top.png");
		into.add("textures/block/" + name + "_side.png");
		into.add("textures/block/" + name + "_front.png");
	}

	private static void send(HttpExchange exchange, int status, String contentType, byte[] body) throws IOException {
		exchange.getResponseHeaders().set("Content-Type", contentType);
		// Wide-open CORS is fine: loopback-only and read-only.
		exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
		exchange.sendResponseHeaders(status, body.length);
		try (OutputStream os = exchange.getResponseBody()) {
			os.write(body);
		}
	}
}
