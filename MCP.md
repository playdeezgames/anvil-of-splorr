# Anvil as an MCP server

Built (all five pieces). **Using it**: build once, then register the binary with any MCP client; `--dir` is the folder world files live in (every path a tool takes is relative to it).

```bash
./build.sh mcp                                                    # build/anvil_mcp
claude mcp add anvil -- "$PWD/build/anvil_mcp" --dir "$PWD/worlds"   # Claude Code; other clients: command + args
build/anvil_mcp --tools > MCP_TOOLS.md                            # regenerate the tool reference
```

The reference for every tool (name, what it does, input schema) is `MCP_TOOLS.md`, generated from the code; a test fails if it is stale. A typical session: `world_new` (or `world_open`), edit with the tag / palette / tileset / terrain / sprite / map / character tools, look with `render_map` and `play_walk`, then `world_save`. `mcp_server/smoke_test.odin` builds a complete "Go Get the Thing" world with tool calls alone and reads it back through `anvil_runtime`, which is the best worked example.

Below is the original plan, kept for the reasoning.

# Plan

Goal: another Claude session or agent authors a world (`world.json`) through MCP tools, without the editors' UI. Decisions made: scope = **author worlds**, implementation = **Odin stdio binary**, results = **PNG pictures**.

## Shape

- New app `apps/anvil_mcp/` (native only, no frontend): `main` reads newline-delimited JSON-RPC 2.0 from stdin and writes responses to stdout (logs to stderr). Methods: `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, `ping`. Protocol version `2025-06-18`; tools only (no resources/prompts at first).
- Package `mcp_server/` holds everything testable: JSON-RPC framing, the tool table, one handler per tool. `apps/anvil_mcp` is a thin `main`. Tests call `handle_request(bytes) -> bytes` with no process.
- It edits the **same model** the editors use (`common/world*.odin`, `World` is ~21 MB: a global, never by value), so every rule (unique names, reference protection, solid tag 0, player/placement rules, size limits) is enforced by the same code. Tools return the model's own refusal text as an MCP tool error (`isError: true`), never a crash.
- One open world per server process. State is in memory; **nothing touches disk until `world_save`**, and `world_open` refuses to replace unsaved changes unless `discard: true`. Paths are relative to a working directory the server is started in (`--dir`), and `..` or absolute paths are refused. It never writes `input_map.json`, `default-font.json` or other user files; saving to an existing file needs `overwrite: true`.
- Names, never indices, in the tool API (the file format is by name too), so an agent cannot desync from reordering.

## Tools (first cut)

| Group | Tools |
|---|---|
| World | `world_new`, `world_open`, `world_save`, `world_summary` (counts, tile size, dirty, tags missing), `world_check_game_tags` (against a `game_tags.json` text or file) |
| Look | `palette_get/set`, `tile_size_set`, tileset: `tileset_list/new/import/delete/rename`, `image_new/delete/rename/get/set_pixels/draw_rect/flood_fill/…` (an image as rows of hex digits 0..F, one char per pixel), terrain sets and terrains (`terrain_*`, with tags), sprite sets and sprites (`sprite_*`) |
| Rules | `tag_list/new/rename/delete`, `param_list/set_number/set_text/delete` |
| Actors | `character_type_*`, `character_*` (create, set type, tags, player, place/unplace), `map_new/delete/resize/set_set`, `map_get` (rows of terrain-letter codes + legend), `map_paint_cells`, `map_fill_rect`, `map_flood_fill`, `map_set_cell_tags` |
| Pictures | `render_map` (zoom, window), `render_tile`, `render_sprite`, `render_palette` → MCP image content (base64 PNG) |
| Play | `play_walk` (list of directions through `anvil_runtime` play; returns where the player ends and the refusal reasons), to test a layout |

Bulk forms exist wherever an agent would otherwise make thousands of calls (map rows, image rows, `paint_cells` with a list).

## Pieces to build

Status: all five pieces done (5: `anvil_mcp --tools` / MCP_TOOLS.md and the smoke test)

Earlier status: pieces 1 to 4 done (piece 4: render_map/tile/sprite/palette, PNG writer) (piece 3: map_*, char_type_*, character_*, player_set, play_walk) (piece 2: tag_*, param_*, palette_*, tile_size_set, tileset_*, image_*, terrain_*, sprite_*)

Piece 1: (`mcp_server/`, `anvil_mcp/`, `./build.sh mcp`; the package is `mcp_server/` and the binary's `main` is `anvil_mcp/`, not under `apps/`, since `apps/` entries are editor frontends).

1. **Skeleton**: JSON-RPC loop, `initialize`/`tools/list`/`tools/call`, error mapping, `world_new/open/save/summary`, tests via `handle_request`. Add `./build.sh native anvil_mcp` and a documented `claude mcp add anvil -- build/anvil_mcp --dir <worlds>` line.
2. **Rules and Look tools** (tags, params, palette, tilesets and images, terrains, sprites).
3. **Actors and maps**, including bulk map operations and `play_walk`.
4. **Pictures**: a tiny PNG encoder (`common/png_write.odin`: stored deflate blocks, CRC32, Adler32; Odin's `core:image` only reads PNG), `render_*` tools built on `world_draw` writing into an RGBA buffer through a `cm.Renderer` implementation, so the picture is exactly what the editor and game draw.
5. **Docs and a smoke test**: `MCP.md` tool reference, a script-free test that opens `anvil_runtime/testdata/demo_world.json`, edits, saves to a temp dir and reloads it.

## Open questions

- **Sound** will need tools once it exists (it is the other next topic); design them together.
- **Concurrency with a human**: if a person has the world editor open on the same file, last write wins. Out of scope; the server only writes on `world_save`.
- **Huge worlds**: tool results must stay small (rows of a window, not whole 64x64x64 dumps); `map_get` takes a window.
- Whether to also ship a read-only `resources` view of the world later.
