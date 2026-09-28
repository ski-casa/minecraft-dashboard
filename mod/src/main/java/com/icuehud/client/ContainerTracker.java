package com.icuehud.client;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.ChestMenu;
import net.minecraft.world.inventory.ShulkerBoxMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.BarrelBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.ChestBlock;
import net.minecraft.world.level.block.ShulkerBoxBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.ChestType;
import net.minecraft.world.phys.BlockHitResult;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Remembers which storage blocks you placed and what was in them the last time
 * you looked. The client only sees a chest's contents while its screen is open,
 * so the list is refreshed on every open and persisted per world under
 * config/icuehud/. Chests found in the world are ignored unless you claim them
 * with the toggle key while they are open.
 */
public class ContainerTracker {
	private static final int BIND_WINDOW_TICKS = 40;     // interaction -> screen open
	private static final int PLACE_WINDOW_TICKS = 20;    // right-click with a chest -> block appears
	private static final int PRUNE_INTERVAL_TICKS = 40;

	private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

	/** One tracked storage block; a double chest is a single entry keyed by its lower-coordinate half. */
	static final class Tracked {
		String dimension;
		int x, y, z;
		String type;                                       // chest, trapped_chest, barrel, shulker_box...
		LinkedHashMap<String, Integer> items = new LinkedHashMap<>();
		long seenAt;                                       // ms epoch of the last content refresh
	}

	private final KeySettings keys;
	private final Map<String, Tracked> tracked = new LinkedHashMap<>();
	private String worldKey = "";
	private boolean dirty;

	ContainerTracker(KeySettings keys) {
		this.keys = keys;
	}

	// Placement + open bookkeeping (client tick thread only).
	// After a right-click holding a storage block, the blocks around the click are
	// watched for a short while; a storage block that was not there before is yours.
	private BlockPos pendingOrigin;
	private java.util.Set<BlockPos> storageBefore = new java.util.HashSet<>();
	private int pendingPlacementUntil;
	private BlockPos lastInteracted;
	private int lastInteractedUntil;
	private AbstractContainerMenu openMenu;
	private String openKey;                                // null when the open container has no known position
	private Tracked openSnapshot;                          // live contents of the open container
	private boolean toggleWasDown;
	private int tickCount;

	// ---- events -----------------------------------------------------------------

	void onUseBlock(Player player, Level level, InteractionHand hand, BlockHitResult hit) {
		BlockPos pos = hit.getBlockPos();
		if (isStorage(level.getBlockState(pos))) {
			lastInteracted = pos.immutable();
			lastInteractedUntil = tickCount + BIND_WINDOW_TICKS;
		}
		ItemStack held = player.getItemInHand(hand);
		if (held.getItem() instanceof BlockItem blockItem && isStorage(blockItem.getBlock())) {
			pendingOrigin = pos.immutable();
			storageBefore = storageAround(level, pendingOrigin);
			pendingPlacementUntil = tickCount + PLACE_WINDOW_TICKS;
			log("right-click with " + IcueHudClient.itemId(held) + " at " + pos.toShortString() + " (" + hand + "), watching for placement");
		}
	}

	/** Storage block positions within one block of the given position (27 cells). */
	private static java.util.Set<BlockPos> storageAround(Level level, BlockPos center) {
		java.util.Set<BlockPos> found = new java.util.HashSet<>();
		for (BlockPos p : BlockPos.betweenClosed(center.offset(-1, -1, -1), center.offset(1, 1, 1))) {
			if (isStorage(level.getBlockState(p))) found.add(p.immutable());
		}
		return found;
	}

	void onBlockBroken(Level level, BlockPos pos) {
		if (!level.isClientSide()) return;
		String dim = dimension(level);
		if (tracked.remove(key(dim, pos)) != null) { dirty = true; return; }
		// The other half of a double chest keyed on its partner.
		for (Direction d : Direction.Plane.HORIZONTAL) {
			if (tracked.remove(key(dim, pos.relative(d))) != null) {
				// Only if that partner was really joined to this block; a neighbouring single chest stays.
				BlockState neighbour = level.getBlockState(pos.relative(d));
				if (neighbour.getBlock() instanceof ChestBlock && neighbour.getValue(ChestBlock.TYPE) != ChestType.SINGLE) {
					dirty = true;
					return;
				}
				// Not joined: put it back.
				Tracked t = new Tracked();
				t.dimension = dim; t.x = pos.relative(d).getX(); t.y = pos.relative(d).getY(); t.z = pos.relative(d).getZ();
				// (contents were lost with the remove; they refresh on the next open)
				tracked.put(key(dim, pos.relative(d)), t);
			}
		}
	}

	void onLeaveWorld() {
		if (!worldKey.isEmpty()) {
			save();
			tracked.clear();
			worldKey = "";
		}
		openMenu = null; openKey = null; openSnapshot = null;
		pendingOrigin = null; lastInteracted = null;
	}

	private static void log(String message) {
		System.out.println(IcueHudClient.LOG_PREFIX + message);
	}

	// ---- per tick -----------------------------------------------------------------

	void tick(Minecraft client, LocalPlayer player) {
		tickCount++;
		String key = computeWorldKey(client);
		if (!key.equals(worldKey)) {
			if (!worldKey.isEmpty()) save();
			worldKey = key;
			load();
		}
		Level level = client.level;
		String dim = dimension(level);

		// A storage block you just placed becomes tracked as soon as it exists.
		if (pendingOrigin != null) {
			for (BlockPos p : storageAround(level, pendingOrigin)) {
				if (storageBefore.contains(p)) continue;
				BlockState state = level.getBlockState(p);
				log("placed " + typeName(state) + " at " + p.toShortString() + " -> tracked");
				track(level, p, state);
				pendingOrigin = null;
				break;
			}
			if (pendingOrigin != null && tickCount > pendingPlacementUntil) {
				log("no new storage block appeared near " + pendingOrigin.toShortString() + " (click did not place one?)");
				pendingOrigin = null;
			}
		}

		// Follow the open container screen.
		AbstractContainerMenu menu = storageMenu(player);
		if (menu != openMenu) {
			openMenu = menu;
			openKey = null;
			openSnapshot = null;
			if (menu != null && (lastInteracted == null || tickCount > lastInteractedUntil)) {
				log("a storage menu opened but no storage block was clicked in the last " + BIND_WINDOW_TICKS + " ticks; cannot place it");
			}
			if (menu != null && lastInteracted != null && tickCount <= lastInteractedUntil) {
				BlockState state = level.getBlockState(lastInteracted);
				if (isStorage(state)) {
					BlockPos primary = primaryPos(level, lastInteracted, state);
					openKey = key(dim, primary);
					openSnapshot = new Tracked();
					openSnapshot.dimension = dim;
					openSnapshot.x = primary.getX(); openSnapshot.y = primary.getY(); openSnapshot.z = primary.getZ();
					openSnapshot.type = typeName(state);
					log("opened " + openSnapshot.type + " at " + primary.toShortString() + ", tracked=" + tracked.containsKey(openKey));
					if (!tracked.containsKey(openKey)) {
						player.sendOverlayMessage(Component.literal("Not counted by the HUD — press " + keys.trackName() + " to track this container"));
					}
				}
			}
		}
		if (menu != null && openSnapshot != null) {
			readContents(menu, openSnapshot);
			Tracked t = tracked.get(openKey);
			if (t != null) {
				t.items = openSnapshot.items;
				t.seenAt = openSnapshot.seenAt;
				t.type = openSnapshot.type;
				dirty = true;
			}
			// Toggle tracking with a key press while the screen is open.
			boolean down = InputConstants.isKeyDown(keys.trackKey());
			if (down && !toggleWasDown) {
				log(keys.trackName() + " pressed in " + openKey);
				if (tracked.containsKey(openKey)) {
					tracked.remove(openKey);
					player.sendOverlayMessage(Component.literal("HUD: container no longer counted"));
				} else {
					Tracked copy = new Tracked();
					copy.dimension = openSnapshot.dimension; copy.x = openSnapshot.x; copy.y = openSnapshot.y; copy.z = openSnapshot.z;
					copy.type = openSnapshot.type; copy.items = new LinkedHashMap<>(openSnapshot.items); copy.seenAt = openSnapshot.seenAt;
					tracked.put(openKey, copy);
					player.sendOverlayMessage(Component.literal("HUD: container counted (" + tracked.size() + " tracked)"));
				}
				dirty = true;
			}
			toggleWasDown = down;
		} else {
			toggleWasDown = false;
		}

		// Forget tracked blocks that are gone (explosions, other players, pistons).
		if (tickCount % PRUNE_INTERVAL_TICKS == 0) {
			List<String> gone = new ArrayList<>();
			for (Map.Entry<String, Tracked> e : tracked.entrySet()) {
				Tracked t = e.getValue();
				if (!t.dimension.equals(dim)) continue;
				BlockPos pos = new BlockPos(t.x, t.y, t.z);
				if (level.hasChunkAt(pos) && !isStorage(level.getBlockState(pos))) gone.add(e.getKey());
			}
			for (String k : gone) { tracked.remove(k); log("tracked block gone at " + k + " -> forgotten"); }
			if (!gone.isEmpty()) dirty = true;
		}

		if (dirty && tickCount % 20 == 0) save();
	}

	// ---- output -----------------------------------------------------------------

	String worldKey() {
		return worldKey;
	}

	JsonArray containersJson() {
		JsonArray arr = new JsonArray();
		for (Map.Entry<String, Tracked> e : tracked.entrySet()) {
			arr.add(trackedJson(e.getKey(), e.getValue(), true));
		}
		return arr;
	}

	JsonElement openContainerJson() {
		if (openMenu == null) return JsonNull.INSTANCE;
		if (openSnapshot == null) {
			JsonObject o = new JsonObject();
			o.addProperty("known", false);
			return o;
		}
		return trackedJson(openKey, openSnapshot, tracked.containsKey(openKey));
	}

	Map<String, Integer> totals() {
		Map<String, Integer> totals = new HashMap<>();
		for (Tracked t : tracked.values()) {
			for (Map.Entry<String, Integer> e : t.items.entrySet()) totals.merge(e.getKey(), e.getValue(), Integer::sum);
		}
		return totals;
	}

	private static JsonObject trackedJson(String key, Tracked t, boolean isTracked) {
		JsonObject o = new JsonObject();
		o.addProperty("key", key);
		o.addProperty("known", true);
		o.addProperty("tracked", isTracked);
		o.addProperty("dimension", t.dimension);
		o.addProperty("x", t.x);
		o.addProperty("y", t.y);
		o.addProperty("z", t.z);
		o.addProperty("type", t.type);
		o.addProperty("seenAt", t.seenAt);
		JsonArray items = new JsonArray();
		for (Map.Entry<String, Integer> e : t.items.entrySet()) {
			JsonObject i = new JsonObject();
			i.addProperty("id", e.getKey());
			i.addProperty("count", e.getValue());
			items.add(i);
		}
		o.add("items", items);
		return o;
	}

	// ---- helpers -----------------------------------------------------------------

	private void track(Level level, BlockPos pos, BlockState state) {
		BlockPos primary = primaryPos(level, pos, state);
		String k = key(dimension(level), primary);
		if (tracked.containsKey(k)) return;
		// Joining a new chest onto a tracked single one: drop the old single entry, the pair re-keys.
		if (state.getBlock() instanceof ChestBlock && state.getValue(ChestBlock.TYPE) != ChestType.SINGLE) {
			tracked.remove(key(dimension(level), pos.relative(ChestBlock.getConnectedDirection(state))));
		}
		Tracked t = new Tracked();
		t.dimension = dimension(level);
		t.x = primary.getX(); t.y = primary.getY(); t.z = primary.getZ();
		t.type = typeName(state);
		t.seenAt = System.currentTimeMillis();
		tracked.put(k, t);
		dirty = true;
	}

	/** The container's slots are the ones not backed by the player's own inventory. */
	private static void readContents(AbstractContainerMenu menu, Tracked into) {
		LinkedHashMap<String, Integer> items = new LinkedHashMap<>();
		for (Slot slot : menu.slots) {
			if (slot.container instanceof Inventory) continue;
			ItemStack stack = slot.getItem();
			if (stack.isEmpty()) continue;
			items.merge(IcueHudClient.itemId(stack), stack.getCount(), Integer::sum);
		}
		into.items = items;
		into.seenAt = System.currentTimeMillis();
	}

	/** The menu the player has open right now; their own inventory menu is never a storage menu. */
	private static AbstractContainerMenu storageMenu(LocalPlayer player) {
		AbstractContainerMenu menu = player.containerMenu;
		if (menu instanceof ChestMenu || menu instanceof ShulkerBoxMenu) return menu;
		return null;
	}

	/** Double chests are keyed on the half with the lower coordinates so both halves map to one entry. */
	private static BlockPos primaryPos(Level level, BlockPos pos, BlockState state) {
		if (state.getBlock() instanceof ChestBlock && state.getValue(ChestBlock.TYPE) != ChestType.SINGLE) {
			BlockPos other = pos.relative(ChestBlock.getConnectedDirection(state));
			return other.compareTo(pos) < 0 ? other : pos;
		}
		return pos;
	}

	private static boolean isStorage(BlockState state) {
		return isStorage(state.getBlock());
	}

	private static boolean isStorage(Block block) {
		return block instanceof ChestBlock || block instanceof BarrelBlock || block instanceof ShulkerBoxBlock;
	}

	private static String typeName(BlockState state) {
		return net.minecraft.core.registries.BuiltInRegistries.BLOCK.getKey(state.getBlock()).getPath();
	}

	private static String dimension(Level level) {
		return level.dimension().identifier().toString();
	}

	private static String key(String dimension, BlockPos pos) {
		return dimension + "|" + pos.getX() + "," + pos.getY() + "," + pos.getZ();
	}

	private static String computeWorldKey(Minecraft client) {
		if (client.getSingleplayerServer() != null) {
			return "sp_" + sanitize(client.getSingleplayerServer().getWorldData().getLevelName());
		}
		if (client.getCurrentServer() != null) {
			// A Realm moves between addresses, so its name is the stable id; a normal server is its address.
			if (client.getCurrentServer().isRealm()) return "realm_" + sanitize(client.getCurrentServer().name);
			return "mp_" + sanitize(client.getCurrentServer().ip);
		}
		return "remote";
	}

	private static String sanitize(String s) {
		String cleaned = s.replaceAll("[^A-Za-z0-9._-]", "_");
		return cleaned.isEmpty() ? "world" : cleaned;
	}

	// ---- persistence -----------------------------------------------------------------

	private Path file() {
		return FabricLoader.getInstance().getConfigDir().resolve("icuehud").resolve("containers-" + worldKey + ".json");
	}

	private void load() {
		tracked.clear();
		dirty = false;
		Path path = file();
		if (!Files.exists(path)) {
			// First time on a Realm since files were keyed by address: gather what the
			// address-named files hold (those are left in place) and continue from there.
			if (worldKey.startsWith("realm_")) migrateLegacyRealmFiles(path);
			return;
		}
		loadFrom(path, false);
		System.out.println(IcueHudClient.LOG_PREFIX + "loaded " + tracked.size() + " tracked containers for " + worldKey);
	}

	private void migrateLegacyRealmFiles(Path target) {
		try (var files = Files.list(target.getParent())) {
			List<Path> legacy = files.filter(p -> p.getFileName().toString().startsWith("containers-mp_")).toList();
			for (Path p : legacy) loadFrom(p, true);
			if (!tracked.isEmpty()) {
				System.out.println(IcueHudClient.LOG_PREFIX + "merged " + tracked.size() + " tracked containers from " + legacy.size() + " address-named files into " + target.getFileName());
				save();
			}
		} catch (IOException e) {
			// nothing to migrate
		}
	}

	/** Reads one save file into `tracked`; with merge=true, existing entries win over the file's. */
	private void loadFrom(Path path, boolean merge) {
		try {
			JsonObject root = JsonParser.parseString(Files.readString(path, StandardCharsets.UTF_8)).getAsJsonObject();
			for (JsonElement el : root.getAsJsonArray("containers")) {
				JsonObject o = el.getAsJsonObject();
				Tracked t = new Tracked();
				t.dimension = o.get("dimension").getAsString();
				t.x = o.get("x").getAsInt(); t.y = o.get("y").getAsInt(); t.z = o.get("z").getAsInt();
				t.type = o.has("type") ? o.get("type").getAsString() : "chest";
				t.seenAt = o.has("seenAt") ? o.get("seenAt").getAsLong() : 0;
				for (JsonElement ie : o.getAsJsonArray("items")) {
					JsonObject i = ie.getAsJsonObject();
					t.items.put(i.get("id").getAsString(), i.get("count").getAsInt());
				}
				String k = key(t.dimension, new BlockPos(t.x, t.y, t.z));
				if (merge && tracked.containsKey(k) && tracked.get(k).seenAt >= t.seenAt) continue;
				tracked.put(k, t);
			}
		} catch (Exception e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "could not read " + path + ": " + e.getMessage());
		}
	}

	private void save() {
		dirty = false;
		if (worldKey.isEmpty()) return;
		JsonObject root = new JsonObject();
		root.addProperty("world", worldKey);
		root.add("containers", containersJson());
		Path path = file();
		try {
			Files.createDirectories(path.getParent());
			Files.writeString(path, GSON.toJson(root), StandardCharsets.UTF_8);
		} catch (IOException e) {
			System.err.println(IcueHudClient.LOG_PREFIX + "could not write " + path + ": " + e.getMessage());
		}
	}
}
