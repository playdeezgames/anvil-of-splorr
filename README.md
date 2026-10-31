# anvil-of-splorr

A suite of small editors for making the art and worlds of games, written in [Odin](https://odin-lang.org). Palettes, 4-bit pictures, tilesets, worlds (terrain, sprites, maps, characters, features, items, triggers, sounds, game parameters), glyphs and fonts, plus a controls editor and a gamepad tester, all behind one main menu. The same code runs natively (SDL2) and in the browser (wasm).

**Try it in the browser: <https://playdeezgames.github.io/anvil-of-splorr/>** (no install; see [PAGES.md](PAGES.md)).

It is built to its maintainer's own specs and taste, and is shared for **forking** rather than collaboration: see [CONTRIBUTING.md](CONTRIBUTING.md).

## What is in it

- **The editors** (`palette_editor`, `image_editor`, `tileset_editor`, `world_editor`, `glyph_editor`, `font_editor`, `controls_editor`, `gamepad_tester`), launched from one main menu (`launcher`). Each is also buildable on its own.
- **Eight commands, three kinds of input.** Tools never see keys or buttons: there are exactly eight commands (up, down, left, right, green, red, blue, yellow) plus the mouse. Every function is reachable by keyboard, mouse or gamepad, and tests enforce it. Bindings and on-screen names live in `input_map.json` and can be edited in the Controls editor.
- **A game-side runtime** (`anvil_runtime/`): what a game imports to load a world, move characters and features around, handle items, collisions and triggers, play sounds and draw. See [GAMES.md](GAMES.md).
- **An MCP server** (`anvil_mcp`): lets an AI session author a world through tool calls and look at it as pictures and sound. See [MCP.md](MCP.md) and [MCP_TOOLS.md](MCP_TOOLS.md).

## Build and run

You need the Odin compiler at the release in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (`ODIN_VERSION`, currently `dev-2026-07`). The native build also needs the SDL2 development libraries (`libsdl2-dev` on Debian and Ubuntu); the web build needs only Odin and clang/llvm. Linux is what is tested.

```bash
git clone https://github.com/playdeezgames/anvil-of-splorr.git
cd anvil-of-splorr
./build.sh test        # unit tests (takes a few minutes)
./build.sh run         # native build and run: the main menu
./build.sh serve       # web build and a local server on http://localhost:8000
```

`./build.sh check` type-checks every package and both frontends. `./build.sh run palette_editor` (or any other tool name) builds one tool on its own. More in the header of [build.sh](build.sh).

Files are saved per tool in the working directory (`palette.json`, `image.json`, `world.json`, `font.json` and so on). In the browser, SAVE keeps a copy in the browser's storage and also downloads it; **Open file** loads one back. Keep the downloads, since browser storage can be cleared.

## Using the MCP server

```bash
./build.sh mcp                                                       # build/anvil_mcp
claude mcp add anvil -- "$PWD/build/anvil_mcp" --dir "$PWD/worlds"   # Claude Code; other clients take the same command and arguments
```

`--dir` is the folder world files live in; every path a tool takes is relative to it. `./build.sh install-mcp` puts a stable copy in `~/.local/bin` for other sessions. Details, including the tools by group, are in [MCP.md](MCP.md); [CLAUDE_SNIPPET.md](CLAUDE_SNIPPET.md) is a block to paste into the `CLAUDE.md` of a game repo that uses it.

## Making a game

A game lives outside this repo and imports `anvil:common` and `anvil:anvil_runtime`:

```bash
APP_DIR=path/to/mygame/app ./build.sh run       # also native, web, serve
```

The recipe, the held-keys and sound APIs and the example in `testdata/external_app` are in [GAMES.md](GAMES.md).

## Docs

- [WORLD.md](WORLD.md): the world model and file format.
- [GAMES.md](GAMES.md): using the runtime from your own game.
- [MCP.md](MCP.md), [MCP_TOOLS.md](MCP_TOOLS.md): the MCP server and every tool (the second is generated).
- [CLAUDE.md](CLAUDE.md): architecture notes for working on this repo.
- [CONTRIBUTING.md](CONTRIBUTING.md): the project is for forking, plus notes for working in a fork.
- [PAGES.md](PAGES.md): the GitHub Pages site and how it is built. [ITCH.md](ITCH.md): notes on packaging the web build as a zip.

## Your own taste

`default-font.json` (the font every tool draws with) and `input_map.json` (key and button bindings) are the maintainer's own and are meant to be replaced in a fork. The demo `world.json`, `image.json` and `bricks.json` are samples.

## License

MIT, see [LICENSE](LICENSE). It covers everything in the repo, including the font, bindings and demo files.
