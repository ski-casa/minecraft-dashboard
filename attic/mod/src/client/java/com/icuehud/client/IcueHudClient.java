package com.icuehud.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;

public class IcueHudClient implements ClientModInitializer {
	public static final int HTTP_PORT = 27421;

	// Fixed slot layout used by the HTTP API, independent of Minecraft's internal indices:
	// 0-8 hotbar, 9-35 storage, 36 feet, 37 legs, 38 chest, 39 head, 40 offhand.
	private static final int SLOT_FEET = 36;
	private static final int SLOT_LEGS = 37;
	private static final int SLOT_CHEST = 38;
	private static final int SLOT_HEAD = 39;
	private static final int SLOT_OFFHAND = 40;

	private final GameState state = new GameState();
	private IcueHttpServer httpServer;

	@Override
	public void onInitializeClient() {
		ClientTickEvents.END_CLIENT_TICK.register(this::onTick);
		httpServer = new IcueHttpServer(state, HTTP_PORT);
		httpServer.start();
		ClientLifecycleEvents.CLIENT_STOPPING.register(client -> httpServer.stop());
		System.out.println("[icuehud] initialized");
	}

	private void onTick(Minecraft client) {
		LocalPlayer player = client.player;
		if (player == null || client.level == null) {
			state.clear();
			return;
		}

		GameState.Coords coords = new GameState.Coords(
				player.getX(), player.getY(), player.getZ(),
				player.getYRot(), player.getXRot(),
				client.level.dimension().identifier().toString());

		List<GameState.Slot> slots = new ArrayList<>();
		Inventory inventory = player.getInventory();
		int mainSize = Math.min(inventory.getContainerSize(), 36);
		for (int i = 0; i < mainSize; i++) {
			addSlot(slots, i, inventory.getItem(i));
		}
		addSlot(slots, SLOT_FEET, player.getItemBySlot(EquipmentSlot.FEET));
		addSlot(slots, SLOT_LEGS, player.getItemBySlot(EquipmentSlot.LEGS));
		addSlot(slots, SLOT_CHEST, player.getItemBySlot(EquipmentSlot.CHEST));
		addSlot(slots, SLOT_HEAD, player.getItemBySlot(EquipmentSlot.HEAD));
		addSlot(slots, SLOT_OFFHAND, player.getItemBySlot(EquipmentSlot.OFFHAND));

		state.set(new GameState.Snapshot(true, coords, slots));
	}

	private static void addSlot(List<GameState.Slot> slots, int index, ItemStack stack) {
		if (stack.isEmpty()) {
			return;
		}
		String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
		slots.add(new GameState.Slot(index, itemId, stack.getCount(),
				stack.getItem().getDefaultMaxStackSize(), stack.getHoverName().getString()));
	}
}
