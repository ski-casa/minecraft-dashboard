package com.icuehud.client;

import com.google.gson.JsonObject;
import com.mojang.blaze3d.platform.InputConstants;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;

import java.util.Set;

/**
 * Things the dashboard can make the game do (POST /action, run on the game
 * thread). Loopback-only, so anything a local page asks for is treated as
 * the player's own input.
 *
 *   { "action": "chat",       "text": "heading home" }   say something
 *   { "action": "command",    "text": "home" }           run /home (leading slash optional)
 *   { "action": "key",        "key": "B" }               press a key binding once (JourneyMap's B, your own, ...)
 *   { "action": "capture" }                              same as the capture hotkey (coords-tap panel)
 *   { "action": "perspective" }                          cycle first/third person
 *   { "action": "screenshot" }
 *   { "action": "message",    "text": "..." }            show text on your own screen only (action bar)
 */
public final class Actions {
	public static final Set<String> NAMES = Set.of("chat", "command", "key", "capture", "perspective", "screenshot", "message");

	private Actions() {}

	public static void run(Minecraft client, LocalPlayer player, JsonObject action, Runnable capture) {
		String name = str(action, "action");
		String text = str(action, "text");
		try {
			switch (name) {
				case "chat" -> { if (!text.isBlank()) player.connection.sendChat(text.strip()); }
				case "command" -> { if (!text.isBlank()) player.connection.sendCommand(text.strip().replaceFirst("^/", "")); }
				case "key" -> {
					int code = KeySettings.resolve(str(action, "key").trim().toUpperCase(java.util.Locale.ROOT));
					if (code >= 0) KeyMapping.click(InputConstants.Type.KEYBOARD.getOrCreate(code));
				}
				case "capture" -> capture.run();
				case "perspective" -> client.options.setCameraType(client.options.getCameraType().cycle());
				case "screenshot" -> net.minecraft.client.Screenshot.grab(client, false);
				case "message" -> player.sendOverlayMessage(Component.literal(text));
				default -> System.err.println(IcueHudClient.LOG_PREFIX + "unknown action " + name);
			}
		} catch (RuntimeException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "action " + name + " failed: " + e);
		}
	}

	private static String str(JsonObject o, String key) {
		return o.has(key) && o.get(key).isJsonPrimitive() ? o.get(key).getAsString() : "";
	}
}
