package com.icuehud.client;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.loader.api.FabricLoader;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

/**
 * The mod's hotkeys, read from config/icuehud/keys.properties so they can be
 * changed without rebuilding. Key names are Minecraft's own (InputConstants.KEY_*
 * without the prefix): letters, digits, F1-F24, NUMPAD0-9, HOME, INSERT, ...
 * The file is re-read while the game runs, so edits apply within seconds.
 */
public class KeySettings {
	public static final String DEFAULT_CAPTURE = "H";
	public static final String DEFAULT_TRACK = "K";

	private String captureName = DEFAULT_CAPTURE;
	private String trackName = DEFAULT_TRACK;
	private int captureKey = InputConstants.KEY_H;
	private int trackKey = InputConstants.KEY_K;
	private long lastModified = -1;

	public int captureKey() { return captureKey; }
	public int trackKey() { return trackKey; }
	public String captureName() { return captureName; }
	public String trackName() { return trackName; }

	private static Path file() {
		return FabricLoader.getInstance().getConfigDir().resolve("icuehud").resolve("keys.properties");
	}

	/** Loads the file if it changed (creating it with the defaults on first run). */
	public void refresh() {
		Path path = file();
		try {
			if (!Files.exists(path)) {
				Files.createDirectories(path.getParent());
				Files.writeString(path, ""
						+ "# iCUE HUD Bridge hotkeys. Names as Minecraft spells them: A-Z, 0-9, F1-F24,\n"
						+ "# NUMPAD0-NUMPAD9, HOME, END, INSERT, PAGEUP, PAGEDOWN, LBRACKET, RBRACKET, ...\n"
						+ "# Saved edits apply while the game runs. An unknown name keeps the previous key.\n"
						+ "\n"
						+ "# Stamp your position onto the dashboard's coords-tap panel (in game, no menu open).\n"
						+ "capture=" + DEFAULT_CAPTURE + "\n"
						+ "\n"
						+ "# While a chest / barrel / shulker box is open: count it for the materials panel (again to un-count).\n"
						+ "trackContainer=" + DEFAULT_TRACK + "\n", StandardCharsets.UTF_8);
			}
			long modified = Files.getLastModifiedTime(path).toMillis();
			if (modified == lastModified) return;
			lastModified = modified;

			Properties props = new Properties();
			try (var in = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
				props.load(in);
			}
			String c = props.getProperty("capture", DEFAULT_CAPTURE).trim().toUpperCase();
			String t = props.getProperty("trackContainer", DEFAULT_TRACK).trim().toUpperCase();
			int ck = resolve(c), tk = resolve(t);
			if (ck >= 0) { captureKey = ck; captureName = c; }
			if (tk >= 0) { trackKey = tk; trackName = t; }
			System.out.println(IcueHudClient.LOG_PREFIX + "keys: capture=" + captureName + " trackContainer=" + trackName);
		} catch (IOException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "could not read " + path + ": " + e.getMessage());
		}
	}

	/** "H", "F8", "NUMPAD5" -> InputConstants.KEY_H / KEY_F8 / KEY_NUMPAD5; -1 for an unknown name. */
	static int resolve(String name) {
		try {
			return InputConstants.class.getField("KEY_" + name).getInt(null);
		} catch (ReflectiveOperationException | RuntimeException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "unknown key name '" + name + "' in keys.properties (see the comment in the file); keeping the previous key");
			return -1;
		}
	}
}
