package com.icuehud.client;

import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

public class GameState {
	public record Coords(double x, double y, double z, float yaw, float pitch, String dimension) {}

	public record Slot(int index, String itemId, int count, int maxCount, String displayName) {}

	public record Snapshot(boolean inGame, Coords coords, List<Slot> slots) {
		static final Snapshot EMPTY = new Snapshot(false, null, List.of());
	}

	private final AtomicReference<Snapshot> current = new AtomicReference<>(Snapshot.EMPTY);

	public void set(Snapshot snapshot) {
		current.set(snapshot);
	}

	public void clear() {
		current.set(Snapshot.EMPTY);
	}

	public Snapshot get() {
		return current.get();
	}
}
