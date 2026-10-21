# User stories

Written from the needs of the demo game "Go Get the Thing!" (`/home/yermom/git/go-get-the-thing`, see its `DESIGN.md`). The role is "game maker" unless stated. Each story ends with acceptance criteria. Ordered by how much the game is blocked without them.

Acceptance review (October 21, 2026, against commit `f92ea49`): `./build.sh check` and `./build.sh test` both pass (all packages, including `anvil_runtime` for `js_wasm32`). Each criterion was checked in the code and the test names below. Nothing was run by hand in a window or browser, so the mouse/keyboard/gamepad claims rest on the tests only. Legend: [x] met, [ ] not met.

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

## 5. Sound effects (nice to have): DEFERRED, as the story allowed

As a game maker, I want to make and name short sound effects, so that a pickup and the game over can be heard.

- [ ] A sound format, editor, playback on both frontends, and a runtime play call: not built.
- [x] "If sound is out of scope for now, record it in `BACKLOG.md`": done, with a description of the intended design and the reason (the only story needing new platform code; the demo game does not use it).
- Decision for this game: it ships silent.

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

## Not requested

Character behaviour data (speed, facing, animation frames) is not needed by this game and is not asked for.

## Result

Stories 1, 2, 3, 4, 6 and 7 are accepted; story 5 is deferred to the backlog on purpose. Nothing blocks starting the game. Next steps live in the game repo: add `game_tags.json` (`thing`, `spawn`), author the world (20x11 room, `player` and `thing` character types, `spawn` cells, parameters such as `round_seconds` and `points_per_thing`), then write the game on `anvil_runtime`.
