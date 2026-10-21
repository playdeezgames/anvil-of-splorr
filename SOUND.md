# Sound: plan

Goal (USER_STORIES 5): make and name short sounds and tunes, play them in the editors on both frontends, and let a game play one by name. Decisions made with the user:

- **Format**: each sound is **PLAY text** in the style of Microsoft BASIC's `PLAY` statement (`T120 O4 L8 C D E P8 G4.`). The file stores the text; a parser turns it into notes. Easy to read, to hand-edit and to write from MCP tools.
- **Voices**: **one square-wave voice** per sound, like `PLAY`. Layering is the game playing several sounds at once.
- **Editing**: **text plus audition**. The text is typed with the keypad, one command plays it, and the screen shows the parsed length or the position of the first error.
- **Limits**: up to **64 sounds**, named like the other entities, each text up to **1024 characters**, each with a **loop** yes/no setting, so one grouping serves effects and music.

## The PLAY dialect

Case-insensitive, spaces ignored. Taken from GW-BASIC / QBasic:

| Command | Meaning |
|---|---|
| `A`..`G` + optional `#`/`+` (sharp) or `-` (flat) + optional length `1`..`64` + dots | a note; each dot lengthens it by half again |
| `On` | octave 0..6 (default 4); `<` down, `>` up one octave |
| `Nn` | note by number 0..84 (0 = rest) |
| `Ln` | default note length 1..64 (1 = whole, 4 = quarter), default 4 |
| `Pn` + dots | pause (rest) of length `n` |
| `Tn` | tempo in quarter notes a minute, 32..255, default 120 |
| `MN` / `ML` / `MS` | normal (7/8 of the length sounding), legato (all), staccato (3/4) |

Not taken: `MF`/`MB` (foreground/background), `X` (substring), `=var;`. Anything else, a number out of range or a missing number is an **error with its character position**; nothing plays from a text with an error. Possible later extensions (not planned): volume `Vn`, duty cycle `Un`.

## Design

- `common/world_sounds.odin`: `Sound {name, text, loop}`, `World.sounds [64]`, add / duplicate / rename / delete, text and loop setters, optional `"sounds": [{"name", "text", "loop"}]` in `world.json`. Names unique, as for other entities.
- `common/play_text.odin` (pure): `play_parse(text) -> notes, error`, where a note is a frequency in Hz (0 = rest), the sounding time and the silent gap in milliseconds. `play_duration_ms`.
- `common/square_synth.odin` (pure, deterministic): notes to mono 16-bit PCM at 22050 Hz with a square wave; plus a WAV writer. A cap on the total length (60 s) keeps renders bounded.
- Playback: an **audio hook** on `cm.Tool` (the tool asks for a PCM buffer to be played or stopped; the frontend does it): SDL2 audio queue on native, Web Audio on the page. Like the renderer, the tool code never touches the platform.
- World editor: a **SOUND** section on the hub with a list (new, duplicate, rename, delete, loop) and a sound screen: the text, the parse result, **green = play/stop**, **yellow = type** (the keypad, which needs a longer-text mode than its current 32 characters), red = back.
- Runtime (`anvil_runtime`): `sound_pcm(world, name) -> []i16` and `sound_loops(world, name)`; a game hands the PCM to the audio sink of its frontend. A game without sound builds without any audio code.
- MCP: `sound_list`, `sound_new`, `sound_set` (text, with parse errors reported), `sound_rename`, `sound_delete`, `sound_loop`, `sound_check` (duration, note count, errors) and `sound_render` (the WAV as MCP audio content, so an agent can hand it to a person or save it). `world_summary` lists the sounds.

## Pieces (in this order; the first three are headless and testable, the agent can use them early)

1. Model and file: `world_sounds.odin`, `"sounds"` in `world.json`, tests (limits, names, round trip, old files without it).
2. PLAY parser and square synth with WAV writer, tests (every command, error positions, pitch of A4 = 440 Hz, durations at tempo, dotted notes, MN/ML/MS, determinism).
3. MCP tools and `world_summary`; regenerate `MCP_TOOLS.md`; install the prod copy.
4. Playback plumbing: `Tool` audio hook, SDL2 and web backends, a stop request, tests for the pure parts.
5. World editor: the SOUND section, list and sound screen, a long-text keypad mode, input parity tests (every sound reachable and playable by commands and by mouse).
6. Runtime `sound_pcm` / `sound_loops`, the docs (`WORLD.md`, `CLAUDE.md`, `TASKS.md`), `BACKLOG.md` entry removed.

## Open points (defaults chosen unless the user says otherwise)

- Sample rate and format: mono 16-bit at 22050 Hz.
- Where the hub shows sounds: a fourth section, SOUND, next to LOOK / RULES / ACTORS.
- Mixing several sounds at once is the game frontend's job (a small mixer of four voices in the native and web backends); the world editor plays one sound at a time.
- Volume is fixed (a moderate level); a `V` command could come later.
