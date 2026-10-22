# Building a game around the Anvil's frontends

A game lives in its own repository and keeps only its own code: an `app` package, its game logic and its `world.json`. The Anvil supplies the window, input (`input_map.json`, gamepads), the canvas, the wasm loader and the runtime (`anvil_runtime`) so a frontend fix reaches the game with a rebuild.

## What the game provides

- A package `app` in a folder (`APP_DIR`, usually `<game>/app`) with `app.odin` exporting `make_tool :: proc() -> cm.Tool`. The frontends call it once and drive the returned `Tool`: `handle_event` for the eight commands and the mouse, `draw` once a frame, and (new) **`update(data, dt_ms)`** once a frame before `draw` with the real milliseconds since the previous frame (fractional, clamped to 100 ms so a hidden tab never ends a round in one step; use it for timers, not draw counts). The editors leave `update` nil. **Presenting**: the frontends draw through a present guard (`common/present_guard.odin`), so `draw` only has to draw: a frame is presented once after `draw` returns unless the tool already called `cm.renderer_present` (the editors do), and calling it yourself is harmless. **Sound**: return `cm.Audio_Request`s from the optional `take_audio` (Play a mono 16-bit sample buffer on one of 4 channels, looping or not; Stop; Stop_All); get one from the world's sounds with `rt.sound_play(world, "pickup", channel)` (looping if the sound is set to), `rt.sound_stop(channel)` and `rt.sound_stop_all()`; check at start-up with `rt.missing_sounds(world, {"pickup", ...})` and `rt.broken_sounds(world)`; `rt.sound_pcm` gives the samples to keep for an effect played often. Rendering is parse plus a square wave, quick for effects. Nothing in `anvil_runtime` touches a device, so a game without sound never calls any of it. On the web, audio starts after the first key press or click.
- The Anvil's packages are imported through a collection, never by relative path: `import cm "anvil:common"` and `import rt "anvil:anvil_runtime"`. `build.sh` always passes `-collection:anvil=<the Anvil repo>`.
- Optionally beside `app.odin` (or in its parent folder): `title.txt` (the web page title; default is the folder name), `input_map.json` (the web page's key and button bindings and on-screen labels instead of the Anvil's; native reads `./input_map.json` from the working directory it is run in) and `game_tags.json`.
- The world: embed it with `#load("world.json")` (see `anvil_runtime/world.odin`) or build the web page with `WEB_FETCH=world.json`.

## Building

Run these from the Anvil repo (or call `<anvil>/build.sh` from anywhere):

```bash
APP_DIR=/path/to/game/app ./build.sh native            # build/<name>, named after the game's folder
APP_DIR=/path/to/game/app ./build.sh run              # build and run it
APP_DIR=/path/to/game/app ./build.sh web              # build/web/<name>/ (page, app.wasm, odin.js, links to input_map.json)
APP_DIR=/path/to/game/app ./build.sh serve 8123       # web + a local server
APP_DIR=... APP_NAME=gtt OUT_DIR=/path/to/game/build ./build.sh web   # a different name and output folder
```

The web steps are the same as for `apps/<name>`: the page title, a link to the chosen `input_map.json` (so edits survive a rebuild), a link to `game_tags.json` if the game has one, `WEB_FETCH`, `WEB_FILE_MIB` and `WEB_OPT`.

## Keeping the recipe honest

`testdata/external_app/` is a tiny stand-in game outside `apps/`: `./build.sh check` builds it for native and `js_wasm32` through exactly the steps above and checks that its own `input_map.json` is the one the page links to. If you change `build.sh` or the frontends and the recipe breaks, that check fails first.

## When a gamepad does nothing (native build)

The native frontend prints, once at start-up on stderr, what SDL sees: `gamepads: SDL sees N, opened M as standard controllers`, a line for each device it ignores because it has no standard controller mapping (only standard layouts produce commands), and, when SDL sees none although `/dev/input` has devices, the first device file this user cannot open.

- **SDL sees none and a path is named**: on Linux SDL reads `/dev/input/event*`, which is often readable only by the `input` group. Join the group (`sudo usermod -aG input $USER`, then log in again) or add a udev rule that gives the logged-in user access. `js*` files being readable is not enough.
- **A device is ignored**: SDL has no standard mapping for it. Add one to the `SDL_GAMECONTROLLERCONFIG` environment variable (SDL's controller database format) and start again.
- **Nothing is printed about permissions and the list is empty**: no pad is plugged in, or the cable or hub is at fault.
- The gamepad tester (a menu entry) shows what the frontend receives, and its empty screen points here. The web build uses the browser's Gamepad API instead: press a button on the pad while the page is focused.
