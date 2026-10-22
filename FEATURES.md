# Features: plan

A **Feature** is like a character that cannot move: a tree, a door, a rock, a sign. It draws a sprite, can carry tags, and stands in at most one cell; **a cell holds at most one feature**. Decisions made with the user:

- **Model: types plus instances**, as for characters. A **Feature Type** (name, sprite, tags) describes what features of the type share; a **Feature** is an instance with a uuid (random version 4, made once, never changed), a name (a label, not unique), its type by name and its own tag settings (inherit / set / cleared per tag, like a character's). A map cell holds a feature's uuid or nothing, and the world keeps one table of features.
- **Overlap: a feature always blocks.** A cell cannot hold both a feature and a character: placing a character on a feature's cell, or a feature on a character's, is refused, and a character cannot step into a cell with a feature (whatever tags say). A feature is therefore always an obstacle; things a character walks onto stay characters (a pickup is a character, as in "Go Get the Thing!").
- **Runtime: a game can change features.** The `Play_State` copies the authored features and a game may remove or place them (open a door, cut a tree); the loaded world is never changed.
- **Limits and places**: up to **64 feature types** (like character types) and up to **2048 features** in the world's table. In the world editor, hub rows **FEATURE TYPES** and **FEATURES** in the ACTORS section, and a **Features layer** in the map editor to place them, one per cell.

## Design

- `common/world_features.odin`: `Feature_Type {name, sprite_set, sprite, tags}`, `Feature {uuid, name, type, tags_set, tags_cleared}`, `World.feature_types [64]`, `World.features [2048]`, and a per-map grid `World_Map.features [64][64]Uuid`; add / duplicate / rename / delete for both (a type cannot be deleted while a feature has it; deleting a feature takes it off its map; sprites and sprite sets that types draw are protected like character types'); `world_place_feature` / `world_unplace_feature` / `world_feature_at` / `world_feature_location`; effective tags `world_feature_has_tag` (its own setting, else its type's). Names unique for types (1..32 printable ASCII), labels only for features.
- Shared cell rule in one place: `world_place_character` refuses a cell with a feature (`Place_Result.Feature`), `world_place_feature` refuses a cell with a character (`.Character`) or another feature (`.Taken`); map flips, rotations and shrinking carry features like characters (a shrink is refused while a feature would be cut off); loading a file with both in one cell is an error.
- File: `"feature_types": [ {"name", "sprite_set", "sprite", "tags": []} ]`, `"features": [ {"uuid", "name", "type", "tags": [], "tags_cleared": []} ]`, and inside each map `"features": [ {"x", "y", "feature": "<uuid>"} ]`, all optional on load.
- Drawing: terrain, then features, then characters (`world_draw_authored_features`, `draw_features` for the play state), through the shared drawing so the editors, play mode and a game agree.
- Editors: `feature_type_editor` and `feature_editor` (copies of the character type and character editors), the map editor's Features layer (`map_editor/features.odin`, like its Characters layer), Tags screens through the shared `Tag_List`. The world editor's Play mode shows features and is blocked by them.
- Runtime (`anvil_runtime`): `feature_count`, `feature_type`, `feature_sprite`, `feature_image`, `feature_has_tag`, `feature_at` (as authored), `features_with_tag`; in `Play_State` features have positions like characters: `play_feature_position`, `play_feature_at`, `play_place_feature`, `play_unplace_feature`; `play_can_step` / `play_step` report `Move_Result.Feature` for a cell with a feature, and `draw_features` draws them.
- MCP: `feature_type_*`, `feature_*` (new, edit, delete, place, unplace, list), `map_get` lists the features in its window, `render_map` draws them, `play_walk` is blocked by them, `world_summary` lists the types.
- Memory: the per-map feature grid adds about 4 MB to a `World` (it is about 21 MB now); a global or `new()` as before.

## Pieces

1. Model and file: `world_features.odin`, the map grids, the shared cell rule, flips/rotations/shrinks, JSON, tests.
2. Feature type editor and feature editor, the hub rows, Tags screens.
3. Map editor Features layer and drawing (terrain < features < characters) in the shared draw code.
4. Runtime queries, `Play_State` features, `Move_Result.Feature`, the world editor's Play mode.
5. MCP tools, `render_map`, `play_walk`, `world_summary`, `MCP_TOOLS.md`, install prod.
6. Docs (`WORLD.md`, `CLAUDE.md`, `TASKS.md`), the demo world, a browser look.

## Open points (defaults unless the user says otherwise)

- The 2048 limit on features (a tree-heavy map could want more; raise it if so).
- Whether a feature's sprite may be left "not set" (shown in red like other missing pictures): yes, as for characters.
- No behaviour data (health, interaction) on features: tags are the only data, as for everything else.
