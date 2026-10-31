# Contributing

**Short version: please fork it.**

The Anvil is published so that you can take it and make your own thing to your own liking. It is built to the maintainer's own taste, and the maintainer is picky about what comes in. Pull requests and feature requests are not sought, will often be declined, and may go unanswered. That's not personal; it just isn't a collaborative project. Forking is the intended way to use it, and the [MIT license](LICENSE) is there to make that easy. It covers everything in the repo, including the maintainer's own font, key bindings and demo world.

If you find a bug, you are welcome to open an issue, but there is no promise it will be looked at on any schedule. A fix in your own fork is always an option.

## Making it your own

The notes below are for working in a fork.

You need the [Odin](https://odin-lang.org) compiler at the version in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (`ODIN_VERSION`), and the SDL2 development libraries for the native build. Run everything from the repo root.

```bash
./build.sh check     # type-check every package, and both frontends for every tool
./build.sh test      # unit tests
./build.sh run       # native build and run (the main menu)
./build.sh serve     # web build and a local server on :8000
./build.sh mcp       # build/anvil_mcp
```

Run one test: `odin test palette_editor -define:ODIN_TEST_NAMES=palette_editor.test_wheel`.

[CLAUDE.md](CLAUDE.md) describes the architecture. In short: each tool is a platform-independent package that takes abstract input and draws through a tiny renderer interface; the native SDL2 frontend and the web (wasm) frontend only implement that interface and translate events, and contain no tool logic. `common/` holds the shared models and file formats, `anvil_runtime/` is what a game imports to use a world, and `mcp_server/` is the MCP server.

- **Add an editor:** write a package that exports `tool(&state) -> cm.Tool` with `enter` and `take_exit`, then add an `Entry` in `apps/suite/app/app.odin`. Nothing in the frontends changes.
- **Make your own game:** build a folder outside the repo with `APP_DIR=<folder> ./build.sh native|web|run|serve`; the recipe is in [GAMES.md](GAMES.md).

Things that are easy to trip over when you change it:

- **Every function must be reachable by keyboard, mouse and gamepad.** Tests (`test_every_*_by_each_input`) enforce it for the editors.
- **Tools:** a refusal is `fail(text)`, never a crash. After adding or changing an MCP tool run `build/anvil_mcp --tools > MCP_TOOLS.md`, or the staleness test fails.
- **Big values:** a `World` is about 35 MB, and a font or tileset about 1 MB. Make them globals or use `new()`, never copy them by value.
- **Odin version:** keep `ODIN_VERSION` in `ci.yml` and the mentions in the docs equal.
- **The maintainer's taste:** `default-font.json` (the font every tool draws with) and `input_map.json` (key and button bindings) are the maintainer's own. A fork should replace them with its own; `GLYPH_H` in `common/font.odin` is checked against the font's height by a test, so re-check the layouts if you change it.
