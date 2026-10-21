# Tasks (from FINDINGS.md and the conversation)

Status: [x] done and committed, [~] done but not committed yet, [ ] to do.

## Image editor
- [x] Flip vertically, flip horizontally (Setup rows + FLIP H / FLIP V buttons)
- [x] Rotate 90 left / 90 right / 180 (width and height swap on a quarter turn)
- [x] Draw a framed rectangle, draw a filled rectangle (FRAME / FILL: keyboard corner placement, mouse drag)
- [x] Flood fill (4-connected region under the cursor, in the current colour)
- [x] Replace colour: every pixel of the colour under the cursor becomes the current colour
- [x] Clear: set the whole image to the current colour

## Glyph editor
- [x] Flip, rotate and rectangles, as in the image editor
- [x] Invert: every "on" pixel becomes "off" and vice versa

## Font editor
- [x] Flip the selected glyph (no rotation, by request)

## Whole suite
- [x] The editors' own text uses the hand-drawn default-font.json instead of the built-in 3x5 font

## Tileset editor (new tool)
- [x] A tileset is a list of images, each with a name; all images share one fixed width and height
- [x] Edit an image with the image editor's tools (reuse, not a copy)
- [x] 90 degree rotation is not offered when the tileset's width and height differ
- [x] Copy and paste images
- [x] Text entry keypad — done and wired to renaming
- [x] Rename an image (uses the keypad)
- [x] Add and delete images; file format (JSON, packed bytes); main menu entry; tests

## World editor (new tool; spec in WORLD.md)
- [~] World model: tile size, one palette, up to 16 tilesets, up to 16 terrain sets, up to 64 maps; JSON file with names, references by name and a per-map terrain name table
- [~] World editor: hub (palette, tile size, lists of tilesets / terrain sets / maps), names by keypad, rename / new / duplicate / delete with reference checks, tileset import from tileset.json
- [~] Palette editor and tileset editor embedded in the world editor (no files, the world sets the tile size)
- [~] Terrain set editor: terrains with name, solid flag, tileset and image (by name), a default terrain, picture picker
- [~] Map editor, patterned on the image editor: paint, flip, rotate (square maps), frame / fill, flood, replace, clear; terrain picker; change terrain set by name
- [~] Sprite sets and sprites: tile reference by name, transparent colour (0..15 or none), background terrain tool, in the world file and the world editor
- [~] Character types and characters (uuid table, cells and player refer by uuid): model and file format, character type editor, character editor, map editor Characters layer
- [~] Tags: a world list ("solid" fixed), set/clear on terrains and character types, inherit/set/clear on characters and map cells, Tags screens in four editors, TAGS list in the world editor, "solid" moved into tags (old files migrate)
- [ ] More asset types in a world (to be specified)

## Game support (from USER_STORIES.md; decisions agreed)
Decisions: the runtime lives in a new `runtime/` package that imports `common`; a game moves characters through a `Play_State` overlay (per-character map and cell, copied from the authored placements) and never mutates or copies the loaded world; required tags come from a hand-edited `game_tags.json` read through a second import-style file; parameters are whole numbers (32-bit) or 32-character texts, up to 64, names unique; sound is deferred to `BACKLOG.md`; play mode moves one step per command press.
- [~] 1. `anvil_runtime/` package (named so because Odin reserves `runtime`): load a world (readable error), find a tag, effective tags of a cell and a character, terrain at a cell, the player and its location, a character's cell and sprite, who is at a cell, `Play_State`; native + `js_wasm32` builds, tests, doc note that a `World` is ~21 MB (global or `new()`)
- [~] 2. Shared drawing in `common` (`world_draw.odin`, used by the map editor and `anvil_runtime`): a window of map cells at a pixel offset and whole-number zoom, a character sprite honouring its transparent colour, clipped not erroring; the map editor uses it
- [~] 3. `game_tags.json` (`common/game_tags.odin`; the world editor asks the frontend for it as a second named file): TAGS marks required tags missing / present / unused, creates the missing ones in one action, warns before renaming or deleting a required tag; the runtime has the same check
- [~] 4. Game parameters (`common/world_params.odin`, hub row PARAMS with a list and a value screen, runtime `param_number`/`param_text`): a hub row of named whole numbers and short texts (new, rename, edit value, delete), saved in `world.json` (optional on load), read by name with a default in the runtime
- [~] 5. Play mode from the world hub (`world_editor/play.odin`, YELLOW or the PLAY button): one step per press, blocked by `solid`, red returns and restores the authored positions (uses 1 and 2)
- [~] 6. A web game can embed (`#load`, documented and tested in `anvil_runtime`) or have the page fetch it (`WEB_FETCH=world.json`); the file buffer size is configurable (`WEB_FILE_MIB`) and documented next to `FILE_CAP`
- [ ] Sound (story 5): planned in `SOUND.md` (PLAY text, one square voice, 64 sounds, below)


## MCP server (plan in MCP.md)
- [x] 1. Skeleton: JSON-RPC over stdio, world_new/open/save/summary/check_game_tags (`mcp_server/`, `anvil_mcp/`, `./build.sh mcp`)
- [x] 2. Rules and Look tools (tags, params, palette, tilesets, images, terrains, sprites)
- [x] 3. Actors and maps, bulk map operations, play_walk
- [x] 4. Pictures: PNG writer and render_* tools
- [x] 5. Tool reference and an end-to-end smoke test

## Sound (plan in SOUND.md)
- [x] 1. Model and file: `common/world_sounds.odin`, `sounds` in world.json
- [x] 2. PLAY parser and square synth with WAV writer (pure, tested)
- [x] 3. MCP sound tools (list/new/set/check/render/export) and installing prod
- [x] 4. Playback hook on `Tool`, SDL2 and web audio
- [x] 5. World editor: sounds in RULES, list, sound screen, long-text keypad, parity tests
- [ ] 6. Runtime `sound_pcm`/`sound_loops`, docs, BACKLOG entry removed

## Game stories 8 and 9 (from the game author, in USER_STORIES.md)
- [x] 8. `Tool.update(data, dt_ms)` called by both frontends, clamped (`common/tool.odin`, `tool_update`, tests)
- [x] 9. External app folders: `APP_DIR`/`APP_NAME`/`OUT_DIR`, `anvil` collection, the game's own `input_map.json` for the web page, `GAMES.md`, a check that builds `testdata/external_app` for native and wasm
