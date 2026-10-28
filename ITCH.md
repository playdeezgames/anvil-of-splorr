# Publishing the web tools on itch.io

The suite (the main menu plus every editor) runs in the browser, so it can be an itch.io HTML5 project for people who would rather not build anything. Nothing here has been uploaded: publishing goes through the release calendar and needs the maintainer's go-ahead (see the end).

## Build the upload

```bash
./build.sh itch            # build/itch/suite.zip
```

This makes a clean web build in `build/itch/stage/suite/` (nothing left over from earlier builds) and zips it with `index.html` at the top, which is what itch's "HTML5" upload wants. The zip holds four files, about 0.7 MB: `index.html`, `app.wasm`, `odin.js` and `input_map.json` (the real file, not a link). The same target takes a single tool, e.g. `./build.sh itch palette_editor`.

The build uses `-o:minimal` (about 20 seconds, `app.wasm` 1.66 MB). `WEB_OPT=speed ./build.sh itch` gives the optimised build, which takes about 11 minutes and makes `app.wasm` 1.40 MB.

## What was checked

Loaded the unzipped build in a page of another origin inside an `<iframe sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-downloads" allow="autoplay; fullscreen">`, which is how itch embeds a game:

- It starts and draws, the keyboard works once the frame has focus (click it first), and so does the mouse.
- SAVE works: "Saved: downloaded world.json and stored in this browser" (browser storage and a download both work inside the frame).
- No special headers are needed: there is no `SharedArrayBuffer`, and the audio is an `AudioWorklet` fed through its message port (see `frontends/web/index.html`).
- The only console message is a 404 for `game_tags.json`, which the page asks for at start and ignores when it is missing.

Not checked: a real itch draft page, Firefox, touch screens (the mouse is the touch input; this is a desktop tool), and frame pacing of the optimised against the default build (the browser pane used for testing stops animating while hidden, so there was no fair way to time frames).

## Decisions made (change them if you disagree)

- **One project, the suite**, not one per tool. A single-tool zip is one `./build.sh itch <tool>` away.
- **No demo world shipped.** The page's fetch-at-start hands a file to the running tool, and the suite starts at the menu, so a shipped `world.json` would not reach the world editor. People start blank, or use the page's **Open file** button.
- **The default build, not `WEB_OPT=speed`**, since the screens are a 320x180 surface of filled rectangles.
- **`FILE_CAP` stays at 4 MiB** (`WEB_FILE_MIB` raises it): the demo world is 12 KB and the largest tileset and font tests fit.
- The shipped `input_map.json` and `default-font.json` are the maintainer's own.

## How saving works on the page (put this on the itch page)

- SAVE stores the file in the browser (local storage for the itch page) **and** downloads it. LOAD restores the last stored copy; **Open file...** loads one from disk.
- Browser storage is per browser and can be cleared, so the download is the real backup.
- Rebinding keys in CONTROLS lasts only for the session on the web unless the downloaded `input_map.json` replaces the served one; on itch, say so and leave it at that.

## Draft page copy

**Title:** Anvil of SPLORR

**Short description:** A suite of small editors for making game assets: palettes, pictures, tilesets, worlds, glyphs and fonts. Keyboard, mouse or gamepad.

**Body:**

> The Anvil is a set of tools for making the art and worlds of small games, built around eight commands so that everything works with a keyboard, a mouse or a gamepad.
>
> **Tools:** Palette Editor (16 colours), Image Editor (4-bit pictures up to 64x64), Tileset Editor, World Editor (tilesets, terrain, sprites, maps, characters, features, items, triggers, sounds, game parameters, and a play mode to walk around it), Glyph Editor, Font Editor, Controls (rebind keys and buttons), and a Gamepad Tester.
>
> **Controls:** arrows move, SPACE/A selects (green), ESC/B goes back (red), ENTER/START opens the file menu (blue), TAB/SELECT is the fourth command (yellow, tool-specific). On a gamepad: d-pad, A/B/Start/Select. The mouse works everywhere. Click the window first so it gets the keyboard.
>
> **Your files:** SAVE keeps a copy in this browser and downloads it; use **Open file...** to load one back. Keep the downloads: browser storage can be cleared.
>
> Source and the game-side runtime (to use these files in your own Odin game): *repository link, once the repo is public*.

**Tags:** tool, pixel-art, level-editor, tileset, game-development
**Kind of project:** HTML. **Embed:** 960 x 540 (the surface is 16:9, 320x180), "click to launch" fullscreen button on.
**Pricing:** the maintainer's call (free, or pay-what-you-like).

## Screenshots

The built-in browser pane can take them: build, serve `build/itch/stage/suite/`, and capture the menu, the palette editor, the world editor map layer and the play mode.

## Before it goes live

Uploading is outward-facing, so: schedule it with coxswain (`ship_schedule`; at most one public release a day across all projects), try it on an unpublished (draft or restricted) itch page first, and ask the maintainer right before the upload and before the page is made public. Upload by hand in the browser, or with `butler` (`butler push build/itch/suite.zip <user>/<game>:html5`); `butler` needs the maintainer's itch login, which never goes in this repo.
