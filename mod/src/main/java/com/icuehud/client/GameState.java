package com.icuehud.client;

import java.util.concurrent.atomic.AtomicReference;

/** The latest state snapshot, already serialized, shared between the game thread and the HTTP thread. */
public class GameState {
	private final AtomicReference<String> json = new AtomicReference<>("{\"inGame\":false}");

	public void set(String snapshotJson) {
		json.set(snapshotJson);
	}

	public String get() {
		return json.get();
	}
}
