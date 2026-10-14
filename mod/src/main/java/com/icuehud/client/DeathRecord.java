package com.icuehud.client;

import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import net.fabricmc.loader.api.FabricLoader;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * The player's last death per world: where, when and in which dimension.
 * Kept in config/icuehud/deaths.json so the dashboard's recovery countdown
 * survives a relog (dropped items despawn five minutes after the death,
 * while their chunk is loaded).
 */
public class DeathRecord {
	private JsonObject byWorld = new JsonObject();   // world key -> { at, x, y, z, dimension }

	private static Path file() {
		return FabricLoader.getInstance().getConfigDir().resolve("icuehud").resolve("deaths.json");
	}

	public void load() {
		Path path = file();
		if (!Files.exists(path)) return;
		try {
			JsonElement e = JsonParser.parseString(Files.readString(path, StandardCharsets.UTF_8));
			if (e.isJsonObject()) byWorld = e.getAsJsonObject();
		} catch (IOException | RuntimeException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "could not read " + path + ": " + e.getMessage());
		}
	}

	public void record(String world, String dimension, double x, double y, double z) {
		JsonObject d = new JsonObject();
		d.addProperty("at", System.currentTimeMillis());
		d.addProperty("x", x);
		d.addProperty("y", y);
		d.addProperty("z", z);
		d.addProperty("dimension", dimension);
		byWorld.add(world == null ? "" : world, d);
		try {
			Path path = file();
			Files.createDirectories(path.getParent());
			Files.writeString(path, byWorld.toString(), StandardCharsets.UTF_8);
		} catch (IOException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "could not write deaths.json: " + e.getMessage());
		}
		System.out.println(IcueHudClient.LOG_PREFIX + String.format(java.util.Locale.ROOT, "death recorded at %.0f / %.0f / %.0f in %s", x, y, z, dimension));
	}

	/** The last death in this world, or JSON null. */
	public JsonElement json(String world) {
		JsonElement d = byWorld.get(world == null ? "" : world);
		return d == null ? JsonNull.INSTANCE : d;
	}
}
