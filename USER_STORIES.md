# User stories

Written from the needs of the demo game "Go Get the Thing!" (`/home/yermom/git/go-get-the-thing`, see its `DESIGN.md`). The role is "game maker" unless stated. Each story ends with acceptance criteria. Ordered by how much the game is blocked without them.

Acceptance review (October 21, 2026, against commit `f92ea49`): `./build.sh check` and `./build.sh test` both pass (all packages, including `anvil_runtime` for `js_wasm32`). Each criterion was checked in the code and the test names below. Nothing was run by hand in a window or browser, so the mouse/keyboard/gamepad claims rest on the tests only. Legend: [x] met, [ ] not met.

> Maintained by the Anvil session: other sessions add stories at the end; the Anvil session works them as directed and ticks them here when done (with what was built).

## 1. Game-side runtime package (blocking): ACCEPTED

As a game maker, I want a package a game can import to load a `world.json` and query it, so that my game does not copy code out of the editors.

- [x] A package exposes load with a readable error; find a tag by name; effective tags of a cell and a character; terrain at a cell; the player and its location; a character's cell and sprite; who is at a cell. (`anvil_runtime`: `load`, `find_tag`, `cell_has_tag`, `character_has_tag`, `terrain_at`, `player`, `authored_location`, `character_sprite`, `play_character_at`; tests `test_a_world_loads_and_a_bad_file_is_refused_with_a_reason`, `..._cells_have_terrain_and_effective_tags`, `..._characters_have_types_sprites_images_and_inherited_tags`.) Named `anvil_runtime` because Odin reserves `runtime`.
- [x] Builds for native and `js_wasm32` and has tests (`build.sh check` runs `odin check anvil_runtime -target:js_wasm32`; 11 tests).
- [x] Documents that a `World` is large and must be a global or `new()` (`anvil_runtime/world.odin`; it says ~21 MB now, not ~17 MB).
- [x] A game changes positions without mutating the world: `Play_State` (about 32 KB, copyable, `play_init` to restart), `play_step`/`play_place`/`play_unplace` (test `..._a_play_state_starts_as_the_authored_world_and_is_separate_from_it`).
- Extra that the game can use: `cells_with_tag` (all cells with a tag, for spawn cells), `param_number`/`param_text`, `required_missing`, and a pickup/respawn loop test (`..._placing_taking_off_and_the_pickup_and_respawn_loop`).

## 2. Draw a map and its characters from a game (blocking): ACCEPTED

As a game maker, I want ready-made drawing of a map region and of characters on the `Renderer`, so that I only decide where things go on the screen.

- [x] Draw terrain for a window of cells at a pixel offset and whole-number zoom (`common/world_draw.odin`: `world_zoom_draw`, `world_draw_terrain`; game wrappers `zoom_window`, `draw_terrain`, `cell_at_pixel`).
- [x] Draw a character's sprite honouring the transparent colour (`world_draw_character`; game wrapper `draw_characters` draws from the `Play_State`, so characters appear where they are now, not where authored; test `..._a_game_draws_the_map_and_where_its_characters_are_now`).
- [x] Clipping, not errors (`test_terrain_is_clipped_not_an_error`, `test_the_clipping_renderer_cuts_and_forwards`; a cell with no picture shows a "missing" colour).
- [x] The map editor and the game share the code (`map_editor/draw.odin` calls `cm.world_draw_terrain` and `world_draw_authored_characters`).

## 3. Games declare the tags they need (important): ACCEPTED

As a game maker, I want to list the tags my game requires and have the Anvil check a world against them, so that a missing `thing` or `spawn` tag is found while editing and not when the game starts.

- [x] A hand-editable requirements file, `game_tags.json` (`{"tags": [{"name", "note"}, "spawn"]}`, note up to 80 characters), read by the world editor from the working directory (native) or beside the page / browser storage (web).
- [x] The TAGS screen marks each tag NEEDED, NEEDED UNUSED, or MISSING (own row); CREATE adds every missing tag in one action (tests in `common/game_tags_test.odin` and `world_editor/editor_test.odin`).
- [x] Renaming or deleting a required tag asks a second time (`WORLD.md`). Missing tags cannot be renamed or deleted.
- [x] The runtime has the same check (`required_missing`, `missing_tags`; test `..._a_game_checks_its_tags_file_against_the_world_at_start_up`).
- To do on the game side: add a `game_tags.json` with `thing` and `spawn` to this game's repo (`solid` is built in).

## 4. Game parameters stored in the world (important): ACCEPTED

As a game maker, I want named numbers and short texts in the world file, so that round length and points per pickup are tuned in the Anvil and not in code.

- [x] Up to 64 named values, names 1..32 printable ASCII and unique; each a whole number (32-bit) or a short text (up to 32 characters). Edited from the PARAMS hub row: new, duplicate, rename, delete (twice), KIND toggle (`common/world_params.odin`; editor tests `test_new_parameter_is_named_then_edited_as_a_number`, `..._a_text_parameter_is_typed_and_kind_switches`, `..._parameters_are_renamed_duplicated_and_deleted_from_the_list`).
- [x] Saved in `world.json`, optional on load (`test_parameters_round_trip_and_old_files_load_without_them`, `test_bad_parameter_data_is_rejected`).
- [x] Runtime reads by name with a default (`param_number`, `param_text`; `test_a_game_reads_parameters_by_name_with_defaults`).
- [x] Uses the same keypad and command model as the other editors (covered by the editor tests above); not exercised by hand here.
- Note: text parameters are limited to 32 characters, which is enough for this game (round length, points per pickup).

## 5. Sound effects (nice to have): DONE (October 22, 2026)

As a game maker, I want to make and name short sound effects, so that a pickup and the game over can be heard.

- [x] A sound format, editor, playback on both frontends, and a runtime play call. Built as SOUND.md describes: a world holds up to 64 named sounds, each BASIC-style PLAY text (one square-wave voice, up to 1024 characters) with a loop flag, saved in `world.json`; the world editor's SOUNDS list and sound screen (play, stop, loop, long-text keypad, parse errors marked); playback through a 4-channel mixer on SDL2 and Web Audio (the web starts audio on the first key press or click); and `anvil_runtime.sound_play(world, name, channel)` with `missing_sounds`, `broken_sounds`, `sound_pcm`, `sound_stop`. MCP tools can store, check, render and export sounds. Tests cover the parser, synth, WAV, mixer, editor screens (commands and mouse) and the runtime; the builder only checked playback in the browser's audio pipeline and with SDL's dummy driver, and on October 22, 2026 the user listened to it in the browser (the world editor's sound screen and the sound demo app) and confirmed that sound works. The user also ran the native SDL2 sound demo on the desktop the same day and confirmed that sound works there too.
- [x] "If sound is out of scope for now, record it in `BACKLOG.md`": done, with a description of the intended design and the reason (the only story needing new platform code; the demo game does not use it).
- Decision for this game: it ships silent; a game that wants sound reads `GAMES.md` (Sound).

## 6. Run a world as a game from the suite (nice to have): ACCEPTED

As a game maker, I want to try a world from the Anvil without leaving the suite, so that I can check that the walls, spawn cells and tags I authored behave as I expect.

- [x] Entry from the hub: YELLOW or the PLAY button. One step per press of the four directions (or a click on a neighbouring cell); blocked by `solid` (effective tag, so a cell's own setting counts), the map edge and other characters, with a message saying why. Red or BACK returns (tests `..._play_needs_a_player_on_a_map`, `..._the_player_steps_and_is_stopped_by_solid_cells_edges_and_characters`, `..._the_view_fits_a_small_map_and_follows_the_player_on_a_big_one`).
- [x] Separate play state; leaving drops it and the authored positions are untouched.
- [x] Reuses stories 1 and 2 (`world_editor/play.odin` is the first user of `anvil_runtime`).
- Gap in the try-out: it does not show `spawn` cells, so authors cannot confirm them visually in play mode (they can on the map editor's cell Tags screen). Not part of the story; mention only.

## 7. Web builds of a game can load the world (nice to have): ACCEPTED

As a game maker, I want a web game to load its `world.json` without the editors' file buffer limits, so that the shipped game is not limited to 4 MiB through the editors' static buffer.

- [x] A game build can embed its world with `#load` (documented in `anvil_runtime/world.odin`, tested by `test_an_embedded_world_file_loads_like_any_other` with `testdata/demo_world.json`), or have the page fetch it (`WEB_FETCH=world.json ./build.sh web <app>`), on native and web.
- [x] The size limit and how to raise it are documented beside `FILE_CAP` in `frontends/web/web.odin` (`WEB_FILE_MIB=<n>`); `BACKLOG.md` marks the game case as settled and leaves only huge-world editing open.

## 8. A game tool knows how much time has passed (important): DONE: ACCEPTED

As a game maker, I want my game's `Tool` to be told how many milliseconds passed since the last frame, so that a countdown timer takes the same real time on a 60 Hz and a 144 Hz display, in a background tab, and on both frontends.

Today `cm.Tool` only has `handle_event` and `draw`; there is no clock, so the game would have to count `draw` calls and assume 60 frames a second. The web `step` already receives `dt` and the SDL2 frontend can read its tick counter; neither passes it on.

- [x] An optional `Tool.update(data, dt_ms)` (nil for the editors), called once per frame by both frontends before `draw`, with the real elapsed milliseconds. (`common/tool.odin`: `Tool.update`, `tool_update`; web `step` passes `dt * 1000`, SDL2 passes the tick difference.)
- [x] `dt_ms` is clamped (for example to 100 ms) so a hidden tab or a dragged window does not make one huge step that ends a round. (`MAX_FRAME_MS` = 100 in `tool_update`; a clock that goes backwards or NaN counts as 0.)
- [x] Both frontends call it, and a test shows a fake frontend loop drives it with given times. (`common/tool_test.odin`: `test_a_tool_is_told_the_elapsed_time_each_frame_clamped`, `..._a_tool_without_a_clock_is_unaffected`; the real SDL2 and browser loops were read, not run.)
- [x] The editors are unchanged and `./build.sh check` and `test` still pass. (Accepted October 21, 2026: `./build.sh check` passed in full, including the external app for native and `js_wasm32`; the two tests above passed; the full `./build.sh test` was not re-run here.)
- Needed by: the round timer in "Go Get the Thing!" (`round_seconds`). Until this exists the game counts frames at an assumed 60 fps.

## 9. Build a game's own app with the Anvil's frontends (important): DONE: ACCEPTED

As a game maker, I want to build the Anvil's native and web frontends around an app that lives in my own repository, so that my game does not copy or fork the frontends and gets every frontend fix (input map, gamepad, canvas, wasm loader) for free.

Today `build.sh` only builds apps found under the Anvil's own `apps/<name>/`, and the frontends import `app:app` plus the Anvil's `common` by relative path. A game can already pass its own `-collection:app=<dir>` to `odin build`, but nothing documents or tests that, and `build.sh`'s web page steps (`input_map.json` link, `game_tags.json` link, `title.txt`, `WEB_FETCH`) would have to be redone by hand.

- [x] `./build.sh native|web` accept an external app folder (for example `APP_DIR=/path/to/game/app`, containing `app.odin` and `title.txt`) and an output folder (`OUT_DIR`), and do the same page steps as for `apps/<name>`. (`APP_DIR` is the folder holding `app.odin`, any name; also `APP_NAME` and `run`/`serve`; see `GAMES.md`.)
- [x] A game can `import` the Anvil's `common` and `anvil_runtime` packages without relative paths into the Anvil repo, by a documented collection (for example `-collection:anvil=<anvil repo>`), and `build.sh` passes it. (`import cm "anvil:common"` and `"anvil:anvil_runtime"`; `-collection:anvil=<repo>` is always passed.)
- [x] The web build can take the game's own `input_map.json` (not only the Anvil's) so a game's bindings and labels are its own. (From `APP_DIR` or its parent; `./build.sh check` verifies the page links it.)
- [x] The way to do this is written in `CLAUDE.md` or a short `GAMES.md`, and one test or check builds a tiny external app for native and `js_wasm32` so the recipe cannot rot. (`GAMES.md`; `testdata/external_app` is built by `./build.sh check`.)
- Needed by: "Go Get the Thing!" (`/home/yermom/git/go-get-the-thing`), which is only an `app/` package, a `game/` package and an embedded `world.json`.

## 10. A game's frame is shown without the game knowing a platform detail (important)

As a game maker, I want the frontends to put a finished frame on the screen themselves, so that a game that only draws works on native and on the web alike.

Found in "Go Get the Thing!" (October 22, 2026): the web build showed the game at once, the native SDL2 window stayed black. The SDL2 frontend calls `tool.draw` and never `renderer.present`; the editors each call `cm.renderer_present(r)` at the end of their draw, the web canvas shows every draw at once, and nothing in `GAMES.md` says a game must present. The game fixed it by presenting itself.

- [ ] Either the SDL2 frontend presents after `tool.draw` (and a tool that also presents is harmless, or the editors stop doing it), or `GAMES.md` says in its "What the game provides" list that `draw` must end with `cm.renderer_present(r)`.
- [ ] The tiny external app in `testdata/external_app` is drawn the same way a real game would be, and `./build.sh check` (or a test) catches an app whose frames are never presented.
- Needed by: any game on the native frontend.

## 11. The native frontend says when it has no usable gamepad (important)

As a game maker, I want to be told why a gamepad does nothing, so that I do not have to debug SDL by hand.

Found while trying the real pad on the native build: a "USB Gamepad" (vendor 0079, product 0011) is plugged in (`/dev/input/js0`, `event16`), the game runs, and the pad does nothing. A probe program with `vendor:sdl2` reports `NumJoysticks = 0`. Cause on this machine: `/dev/input/event16` is `root:input`, mode `rw-rw----`, and the user is not in the `input` group and has no ACL, so SDL's evdev driver cannot open it (`js0` is world readable, but SDL does not use it). The frontend gives no hint: no pad, no message. (Pads SDL has no standard mapping for are also ignored silently, per `CLAUDE.md`.)

- [ ] At start-up the SDL2 frontend prints one line to stderr about gamepads: how many SDL sees, how many it opens as standard controllers, and the name of any device it ignores because it has no standard mapping.
- [ ] If SDL sees none but `/dev/input/js*` or `event*` files exist, it prints a line saying the devices may not be readable by this user (the `input` group or a udev rule), naming the first unreadable path.
- [ ] The same goes in `GAMES.md` and the gamepad tester's help (what to check when a pad is not found).
- Needed by: trying a gamepad on any native build. The user's fix on this machine is outside the repos (the `input` group or a udev ACL).

## 12. `world_save` without a path after the first save (MCP bug)

As a game maker, I want `world_save` with no path to keep working, so that the tool behaves as its description says ("without a path it saves to the file it was opened from or last saved to").

Found on the prod MCP (October 21-22, 2026): after a save, `world_summary` shows `"file"` as a string of NUL bytes (`"\u0000\u0000..."`, 15 of them) and a later `world_save` with no path fails with "the path must end in .json"; the result of a no-path save also prints the NUL string as the file. Saving with an explicit `path` works, and so does `world_export`. The file name seems to be kept as a pointer to memory that is freed (a temp-allocator string) rather than a copy.

- [ ] After `world_new`+`world_save path=x.json`, or `world_open x.json`, the summary shows `x.json` and a pathless `world_save` writes it, repeatedly and after other tool calls.
- [ ] A test calls several tools between two saves and checks the file name is intact.

## Not requested

Character behaviour data (speed, facing, animation frames) is not needed by this game and is not asked for.

## Result

Stories 1, 2, 3, 4, 6 and 7 are accepted; story 5 is deferred to the backlog on purpose. Nothing blocks starting the game. Next steps live in the game repo: add `game_tags.json` (`thing`, `spawn`), author the world (20x11 room, `player` and `thing` character types, `spawn` cells, parameters such as `round_seconds` and `points_per_thing`), then write the game on `anvil_runtime`.
