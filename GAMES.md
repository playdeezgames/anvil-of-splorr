# Building a game around the Anvil's frontends

A game lives in its own repository and keeps only its own code: an `app` package, its game logic and its `world.json`. The Anvil supplies the window, input (`input_map.json`, gamepads), the canvas, the wasm loader and the runtime (`anvil_runtime`) so a frontend fix reaches the game with a rebuild.

## What the game provides

- A package `app` in a folder (`APP_DIR`, usually `<game>/app`) with `app.odin` exporting `make_tool :: proc() -> cm.Tool`. The frontends call it once and drive the returned `Tool`: `handle_event` for the eight commands and the mouse, `draw` once a frame, and (new) **`update(data, dt_ms)`** once a frame before `draw` with the real milliseconds since the previous frame (fractional, clamped to 100 ms so a hidden tab never ends a round in one step; use it for timers, not draw counts). The editors leave `update` nil. **Presenting**: the frontends draw through a present guard (`common/present_guard.odin`), so `draw` only has to draw: a frame is presented once after `draw` returns unless the tool already called `cm.renderer_present` (the editors do), and calling it yourself is harmless. **Sound**: return `cm.Audio_Request`s from the optional `take_audio` (Play a mono 16-bit sample buffer on one of 4 channels, looping or not; Stop; Stop_All); get one from the world's sounds with `rt.sound_play(world, "pickup", channel)` (looping if the sound is set to), `rt.sound_stop(channel)` and `rt.sound_stop_all()`; check at start-up with `rt.missing_sounds(world, {"pickup", ...})` and `rt.broken_sounds(world)`; `rt.sound_pcm` gives the samples to keep for an effect played often. Rendering is parse plus a square wave, quick for effects. Nothing in `anvil_runtime` touches a device, so a game without sound never calls any of it. On the web, audio starts after the first key press or click.
- The Anvil's packages are imported through a collection, never by relative path: `import cm "anvil:common"` and `import rt "anvil:anvil_runtime"`. `build.sh` always passes `-collection:anvil=<the Anvil repo>`.
- Optionally beside `app.odin` (or in its parent folder): `title.txt` (the web page title; default is the folder name), `input_map.json` (the web page's key and button bindings and on-screen labels instead of the Anvil's; native reads `./input_map.json` from the working directory it is run in) and `game_tags.json`.
- The world: embed it with `#load("world.json")` (see `anvil_runtime/world.odin`) or build the web page with `WEB_FETCH=world.json`.

## Building

Run these from the Anvil repo (or call `<anvil>/build.sh` from anywhere):

```bash
APP_DIR=/path/to/game/app ./build.sh native            # build/<name>, named after the game's folder
APP_DIR=/path/to/game/app ./build.sh run              # build and run it
APP_DIR=/path/to/game/app ./build.sh web              # build/web/<name>/ (page, app.wasm, odin.js, links to input_map.json)
APP_DIR=/path/to/game/app ./build.sh serve 8123       # web + a local server
APP_DIR=... APP_NAME=gtt OUT_DIR=/path/to/game/build ./build.sh web   # a different name and output folder
```

The web steps are the same as for `apps/<name>`: the page title, a link to the chosen `input_map.json` (so edits survive a rebuild), a link to `game_tags.json` if the game has one, `WEB_FETCH`, `WEB_FILE_MIB` and `WEB_OPT`.

## Keeping the recipe honest

`testdata/external_app/` is a tiny stand-in game outside `apps/`: `./build.sh check` builds it for native and `js_wasm32` through exactly the steps above and checks that its own `input_map.json` is the one the page links to. If you change `build.sh` or the frontends and the recipe breaks, that check fails first.

## Saving progress

A game that wants a save file sets the file hooks on its `cm.Tool`: `default_file` (say `"save.json"`), `wants_load` (true once, at start, and again whenever the game asks to reload), `load(bytes) -> bool` (false for a file it cannot read, which leaves the game as it was) and one or both of:

- `take_save`: a save the player asked for. Native writes the file in the working directory; the web stores it in browser storage **and offers it as a download** ("Saved: downloaded ...").
- `take_autosave`: the same, for a save the game makes by itself (after every purchase, say). Native writes the file exactly as for `take_save`; the web stores it in browser storage and nothing else: no download, no message.

Both return `(text, ok)`, with `ok` true once per request and the text on the temp allocator; `saved` is called after the frontend has written either kind. At start the web page restores the game's file from browser storage when `wants_load` answers true, with no "Open file" button and nothing on screen unless the stored text is refused by `load`. If browser storage is unavailable (a private window) the page says so once and the game carries on, simply not keeping its saves. Native never reports a missing file; an unreadable or refused one goes to stderr. `testdata/external_app` shows all of it (yellow counts a press and autosaves the count).

## When a gamepad does nothing (native build)

The native frontend prints, once at start-up on stderr, what SDL sees: `gamepads: SDL sees N, opened M as standard controllers`, a line for each device it ignores because it has no standard controller mapping (only standard layouts produce commands), and, when SDL sees none although `/dev/input` has devices, the first device file this user cannot open.

- **SDL sees none and a path is named**: on Linux SDL reads `/dev/input/event*`, which is often readable only by the `input` group. Join the group (`sudo usermod -aG input $USER`, then log in again) or add a udev rule that gives the logged-in user access. `js*` files being readable is not enough.
- **A device is ignored**: SDL has no standard mapping for it. Add one to the `SDL_GAMECONTROLLERCONFIG` environment variable (SDL's controller database format) and start again.
- **Nothing is printed about permissions and the list is empty**: no pad is plugged in, or the cable or hub is at fault.
- The gamepad tester (a menu entry) shows what the frontend receives, and its empty screen points here. The web build uses the browser's Gamepad API instead: press a button on the pad while the page is focused.

## Features and collisions

Features (trees, doors, signs) stand still and always block. A game loads them with the world and gets them from `anvil_runtime`: `feature_count`, `feature_type`, `feature_sprite`/`feature_image`, `feature_has_tag`, `feature_at`, `features_with_tag`. In play they live in the `Play_State` (`play_feature_at`, `play_unplace_feature`, `play_place_feature`); draw them with `draw_features` before `draw_characters`.

To react when something is bumped, drain the collision queue after stepping:

```odin
rt.play_step(&ps, w, player, dx, dy)
for c, ok in rt.play_take_collision(&ps); ok; c, ok = rt.play_take_collision(&ps) {
	switch c.kind {
	case .Feature:   // c.other is a feature index; ask its tags
		if rt.feature_has_tag(w, c.other, door_tag) { rt.play_unplace_feature(&ps, c.other) } // open it
	case .Character: // c.other is a character index
		...
	}
}
```

A `Collision` has the mover (a character index), `kind`, `other`, the map and target cell, and the step (`dx`, `dy`). Only steps refused by a character or a feature queue one; walls and map edges do not. The queue holds 64 (oldest dropped, counted in `collisions_lost`) and `play_init` empties it.

## Items and inventories

Items live in inventories (see `WORLD.md`): a character, a feature or a map cell holds one, and an entry in it is a stack of an item type with a count and its own property values (a sword at durability 40 is a stack of one; gold is a stack of up to the type's max stack). Item types come from `anvil_runtime` as authored (`find_item_type`, `item_type_max_stack`, `item_prop_index`, `item_prop_default`, `item_type_sprite`/`item_type_image`); `play_init` copies the authored inventories into the `Play_State`, and everything a game does happens there:

```odin
hero := rt.owner_character(player)
gold, _ := rt.find_item_type(w, "gold")
rt.play_add_item(&ps, w, hero, gold, 10)                  // joins a stack that matches, else makes entries
rt.play_step(&ps, w, player, dx, dy)                      // stepping onto items is never refused...
for c, ok := rt.play_take_contact(&ps); ok; c, ok = rt.play_take_contact(&ps) {
	rt.play_transfer_all(&ps, w, rt.owner_cell(c.map_index, c.x, c.y), hero) // ...the game picks them up
}
dur, _ := rt.item_prop_index(w, sword_type, "durability")
if e := rt.play_entry(&ps, hero, 0); e != nil {
	left := rt.play_entry_value(&ps, w, e, dur)           // its own value, else the type's default
	rt.play_set_entry_value(&ps, w, hero, 0, dur, left - 1)
}
```

A `Contact` has the mover, the map, the cell entered and the step; the queue holds 64 like collisions. Entries are numbered from 0 in the order the inventory holds them and the numbers change when entries come or go, so look again after a change. An inventory that runs empty is gone. Draw cell inventories with `draw_inventories` after `draw_terrain` and before `draw_features`. The `Play_State` is about 0.9 MB: keep it in a global or `new()` it.

## Numeric properties of characters and features

Character types and feature types can have named whole-number properties (health, speed, locked) with defaults, and a single character or feature can have its own value (see `WORLD.md`). A game looks the property up by name once and keeps its position:

```odin
health, _ := rt.character_prop_index(w, hero, "health")
max_health := rt.character_prop_default(w, hero, health)    // the type's default
rt.play_init(&ps, w)                                        // copies what the authors set
left := rt.play_character_value(&ps, w, hero, health)      // the value now
rt.play_set_character_value(&ps, w, hero, health, left - 3) // changes the play state only, never the world
```

`character_value`/`feature_value` give what the authors set. A value equal to the type's default is stored as no value, so setting it back to the default is the same as never having changed it. The same procs with `feature` in the name work for features.

## Triggers (traps)

A trigger sits in a map cell or on a feature and never blocks (see `WORLD.md`). The Anvil only notifies; your game decides what happens. After a step, drain the queue:

```odin
for e, ok in rt.play_take_triggered(&ps); ok; e, ok = rt.play_take_triggered(&ps) {
	switch e.kind {
	case .Entered: // the mover is in cell e.x,e.y now
		if rt.trigger_has_tag(w, e.trigger, trap_tag) && !rt.character_has_tag(w, e.mover, flies_tag) {
			dmg, _ := rt.trigger_prop_index(w, e.trigger, "damage")
			// ... lower the mover's health by rt.play_trigger_value(&ps, w, e.trigger, dmg)
		}
	case .Bumped: // the step was refused; e.reason is .Feature, .Character or .Solid
	}
}
```

`Entered` is queued for every trigger in the cell a successful step entered; `Bumped` for every trigger in the cell a refused step tried to enter, and, when a feature was in the way, for every trigger on that feature. `Triggered` has the mover and trigger (indexes), `kind`, `reason`, the map and cell, and the step. The queue holds 64 (oldest dropped, `triggered_lost`) and `play_init` empties it. As authored: `trigger_count`, `trigger_type`, `trigger_sprite/_image`, `trigger_has_tag`, `triggers_with_tag`, `trigger_prop_index/_default/_value`, `authored_trigger_cell/_feature`. In play (all in the `Play_State`, never the world): `play_trigger_place`, `play_triggers_in_cell`, `play_triggers_on_feature`, `play_place_trigger`, `play_attach_trigger`, `play_unplace_trigger` (a spent trap), `play_trigger_value`/`play_set_trigger_value`. Draw with `draw_triggers` after `draw_terrain` and before `draw_inventories`; skip it, or draw single ones with `cm.world_draw_trigger`, to keep a trap hidden.
