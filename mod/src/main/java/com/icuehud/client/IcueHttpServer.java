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

	/** Item sprite if there is one, else the block's face; 3D-only models (chests, stairs...) have neither. */
	private static byte[] loadIcon(Identifier item) {
		String ns = item.getNamespace(), name = item.getPath();
		String[] candidates = {
				"textures/item/" + name + ".png",
				"textures/block/" + name + ".png",
				"textures/block/" + name + "_top.png",
				"textures/block/" + name + "_side.png",
				"textures/block/" + name + "_front.png"
		};
		for (String path : candidates) {
			Optional<Resource> res = Minecraft.getInstance().getResourceManager().getResource(Identifier.fromNamespaceAndPath(ns, path));
			if (res.isEmpty()) continue;
			try (InputStream in = res.get().open()) {
				return in.readAllBytes();
			} catch (IOException e) {
				// try the next candidate
			}
		}
		return NO_ICON;
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
