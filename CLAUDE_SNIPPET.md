# CLAUDE.md snippet for sessions using the Anvil's MCP server

Paste the block below into the `CLAUDE.md` of a game repo whose Claude sessions author their world through the `anvil` MCP server (see [MCP.md](MCP.md) for building and registering it). Change the folder name if you registered the server with a different `--dir`.

````markdown
## World authoring (anvil MCP)

This game's world is authored with the `anvil` MCP tools (`world_open`, `world_summary`, `map_*`, `terrain_*`, `render_map`, ...). Every tool is listed in the Anvil's MCP_TOOLS.md.

- Open the world with `world_open` (or `world_new`) before editing. Nothing reaches disk until `world_save`; `world_open` refuses to replace unsaved changes unless `discard: true`, and saving over another file needs `overwrite: true`.
- Name things, never index them. A refused edit explains why; read the message and adjust rather than retrying.
- Look at what you built: `render_map`, `render_tile`, `render_sprite` and `render_palette` return pictures, and `play_walk` tries a route with the game's own movement rules. Check the result before saving.
- `world_check_game_tags` compares the world to the game's `game_tags.json`: fix missing tags before shipping.
- Never edit `world.json` by hand while a session has it open.
````
