package com.icuehud.client;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.event.client.player.ClientPlayerBlockBreakEvents;
import net.fabricmc.fabric.api.event.player.UseBlockCallback;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;

import java.util.Map;

/**
 * Client entry point. Every tick it rebuilds a JSON snapshot of the player's
 * inventory, equipment and tracked containers; {@link IcueHttpServer} hands
 * that snapshot to the dashboard widgets.
 */
public class IcueHudClient implements ClientModInitializer {
	public static final int HTTP_PORT = 27421;
	public static final String LOG_PREFIX = "[icuehud] ";

	// Fixed slot layout used by the API, independent of Minecraft's internal indices:
	// 0-8 hotbar, 9-35 storage, then the equipment by name.
	private static final int MAIN_SLOTS = 36;

	// Hotkeys live in config/icuehud/keys.properties (see KeySettings).
	private final KeySettings keys = new KeySettings();
	private final GameState state = new GameState();
	private final ContainerTracker tracker = new ContainerTracker(keys);
	private IcueHttpServer httpServer;
	private int tick;
	private boolean captureKeyWasDown;
	private JsonObject lastCapture;   // null until the key is first pressed this session

	@Override
	public void onInitializeClient() {
		UseBlockCallback.EVENT.register((player, level, hand, hit) -> {
			if (level.isClientSide()) tracker.onUseBlock(player, level, hand, hit);
			return InteractionResult.PASS;
		});
		ClientPlayerBlockBreakEvents.AFTER.register((level, player, pos, blockState) -> tracker.onBlockBroken(level, pos));
		ClientTickEvents.END_CLIENT_TICK.register(this::onTick);

		keys.refresh();
		httpServer = new IcueHttpServer(state, HTTP_PORT);
		httpServer.start();
		ClientLifecycleEvents.CLIENT_STOPPING.register(client -> httpServer.stop());
		System.out.println(LOG_PREFIX + "initialized");
	}

	private void onTick(Minecraft client) {
		LocalPlayer player = client.player;
		if (player == null || client.level == null) {
			tracker.onLeaveWorld();
			state.set("{\"inGame\":false}");
			return;
		}
		if (++tick % 100 == 0) keys.refresh();   // pick up edits to keys.properties every 5 s
		tracker.tick(client, player);

		// Capture key: only while no screen (menu, chat, chest) is open, so typing never triggers it.
		boolean captureDown = client.gui.screen() == null
				&& com.mojang.blaze3d.platform.InputConstants.isKeyDown(keys.captureKey());
		if (captureDown && !captureKeyWasDown) {
			JsonObject c = new JsonObject();
			c.addProperty("at", System.currentTimeMillis());
			c.addProperty("x", player.getX());
			c.addProperty("y", player.getY());
			c.addProperty("z", player.getZ());
			c.addProperty("dimension", client.level.dimension().identifier().toString());
			lastCapture = c;
			player.sendOverlayMessage(net.minecraft.network.chat.Component.literal(
					String.format(java.util.Locale.ROOT, "HUD: captured %.0f / %.0f / %.0f", player.getX(), player.getY(), player.getZ())));
		}
		captureKeyWasDown = captureDown;

		// Serializing 40+ stacks is cheap, but 20 times a second is more than any widget polls.
		if (tick % 4 != 0) return;

		JsonObject root = new JsonObject();
		root.addProperty("inGame", true);
		root.addProperty("world", tracker.worldKey());
		root.addProperty("dimension", client.level.dimension().identifier().toString());

		JsonObject pos = new JsonObject();
		pos.addProperty("x", player.getX());
		pos.addProperty("y", player.getY());
		pos.addProperty("z", player.getZ());
		root.add("player", pos);

		Map<String, Integer> inventoryTotals = new java.util.HashMap<>();
		JsonArray inventory = new JsonArray();
		Inventory inv = player.getInventory();
		int mainSize = Math.min(inv.getContainerSize(), MAIN_SLOTS);
		for (int i = 0; i < mainSize; i++) {
			ItemStack stack = inv.getItem(i);
			if (stack.isEmpty()) continue;
			JsonObject slot = stackJson(stack);
			slot.addProperty("slot", i);
			inventory.add(slot);
			inventoryTotals.merge(itemId(stack), stack.getCount(), Integer::sum);
		}
		root.add("inventory", inventory);

		JsonObject equipment = new JsonObject();
		equipment.add("head", equipmentJson(player.getItemBySlot(EquipmentSlot.HEAD)));
		equipment.add("chest", equipmentJson(player.getItemBySlot(EquipmentSlot.CHEST)));
		equipment.add("legs", equipmentJson(player.getItemBySlot(EquipmentSlot.LEGS)));
		equipment.add("feet", equipmentJson(player.getItemBySlot(EquipmentSlot.FEET)));
		equipment.add("mainhand", equipmentJson(player.getItemBySlot(EquipmentSlot.MAINHAND)));
		equipment.add("offhand", equipmentJson(player.getItemBySlot(EquipmentSlot.OFFHAND)));
		root.add("equipment", equipment);

		root.add("capture", lastCapture == null ? com.google.gson.JsonNull.INSTANCE : lastCapture);
		JsonObject keyNames = new JsonObject();
		keyNames.addProperty("capture", keys.captureName());
		keyNames.addProperty("trackContainer", keys.trackName());
		root.add("keys", keyNames);
		root.add("containers", tracker.containersJson());
		root.add("openContainer", tracker.openContainerJson());

		// Per item: what is in your inventory and what is in tracked containers.
		JsonObject totals = new JsonObject();
		Map<String, Integer> containerTotals = tracker.totals();
		java.util.Set<String> ids = new java.util.TreeSet<>(inventoryTotals.keySet());
		ids.addAll(containerTotals.keySet());
		for (String id : ids) {
			JsonObject t = new JsonObject();
			t.addProperty("inventory", inventoryTotals.getOrDefault(id, 0));
			t.addProperty("containers", containerTotals.getOrDefault(id, 0));
			totals.add(id, t);
		}
		root.add("totals", totals);

		state.set(root.toString());
	}

	static String itemId(ItemStack stack) {
		return BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
	}

	static JsonObject stackJson(ItemStack stack) {
		JsonObject o = new JsonObject();
		o.addProperty("id", itemId(stack));
		o.addProperty("name", stack.getHoverName().getString());
		o.addProperty("count", stack.getCount());
		o.addProperty("maxCount", stack.getMaxStackSize());
		if (stack.isDamageableItem()) {
			o.addProperty("damage", stack.getDamageValue());
			o.addProperty("maxDamage", stack.getMaxDamage());
		}
		return o;
	}

	private static com.google.gson.JsonElement equipmentJson(ItemStack stack) {
		return stack.isEmpty() ? com.google.gson.JsonNull.INSTANCE : stackJson(stack);
	}
}
