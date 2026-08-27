package com.icuehud.client;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Executors;

public class IcueHttpServer {
	private final GameState state;
	private final int port;
	private HttpServer server;

	public IcueHttpServer(GameState state, int port) {
		this.state = state;
		this.port = port;
	}

	public void start() {
		try {
			// Bound to loopback only: this data never needs to leave the PC.
			server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
			server.createContext("/coords", this::handleCoords);
			server.createContext("/inventory", this::handleInventory);
			server.setExecutor(Executors.newSingleThreadExecutor(r -> {
				Thread t = new Thread(r, "icuehud-http");
				t.setDaemon(true);
				return t;
			}));
			server.start();
			System.out.println("[icuehud] HTTP server listening on 127.0.0.1:" + port);
		} catch (IOException e) {
			System.err.println("[icuehud] Failed to start HTTP server on port " + port + ": " + e.getMessage());
		}
	}

	public void stop() {
		if (server != null) {
			server.stop(0);
		}
	}

	private void handleCoords(HttpExchange exchange) throws IOException {
		GameState.Snapshot snap = state.get();
		String json;
		if (!snap.inGame() || snap.coords() == null) {
			json = "{\"inGame\":false}";
		} else {
			GameState.Coords c = snap.coords();
			json = String.format(Locale.ROOT,
					"{\"inGame\":true,\"x\":%.2f,\"y\":%.2f,\"z\":%.2f,\"yaw\":%.1f,\"pitch\":%.1f,\"dimension\":\"%s\"}",
					c.x(), c.y(), c.z(), c.yaw(), c.pitch(), escape(c.dimension()));
		}
		sendJson(exchange, json);
	}

	private void handleInventory(HttpExchange exchange) throws IOException {
		GameState.Snapshot snap = state.get();
		StringBuilder sb = new StringBuilder();
		sb.append("{\"inGame\":").append(snap.inGame()).append(",\"slots\":[");
		List<GameState.Slot> slots = snap.slots();
		for (int i = 0; i < slots.size(); i++) {
			GameState.Slot s = slots.get(i);
			if (i > 0) sb.append(',');
			sb.append(String.format(Locale.ROOT,
					"{\"index\":%d,\"itemId\":\"%s\",\"count\":%d,\"maxCount\":%d,\"name\":\"%s\"}",
					s.index(), escape(s.itemId()), s.count(), s.maxCount(), escape(s.displayName())));
		}
		sb.append("]}");
		sendJson(exchange, sb.toString());
	}

	private static String escape(String s) {
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}

	private void sendJson(HttpExchange exchange, String json) throws IOException {
		exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
		// Wide-open CORS is fine: server is loopback-only and read-only.
		exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
		byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
		exchange.sendResponseHeaders(200, bytes.length);
		try (OutputStream os = exchange.getResponseBody()) {
			os.write(bytes);
		}
	}
}
