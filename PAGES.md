# The GitHub Pages site

The suite (the main menu and every editor) is published as a static site at <https://playdeezgames.github.io/anvil-of-splorr/>, for people who would rather not build anything. It replaces the earlier idea of an itch.io page; the notes in [ITCH.md](ITCH.md) about the zip build still hold.

## How it is built and deployed

```bash
./build.sh pages        # build/pages/site/
```

This makes a clean web build (`-o:minimal`, about 40 seconds, `app.wasm` 1.66 MB) in `build/pages/site/` with real files only (a Pages artifact may not hold symlinks): `index.html`, `app.wasm`, `odin.js`, `input_map.json`, `about.html` (controls, saving, links) and `.nojekyll`. The page's own fetches and script are relative, so the `/anvil-of-splorr/` subpath works; this was checked by serving the folder under that path.

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) builds it with the pinned Odin and deploys with `actions/deploy-pages`. It runs **only when started by hand** (Actions tab, "Pages", Run workflow), so a push never publishes. One-time setup in the repo's Settings: Pages, Source = **GitHub Actions**.

## Decisions

- **The suite only.** A single-tool site is one `./build.sh web <tool>` away.
- **No demo world.** The suite starts at the menu, so a fetched world would not reach the world editor. People start blank or use **Open file...**.
- **`-o:minimal`**, not `WEB_OPT=speed` (about 11 minutes for 0.26 MB less).
- **`FILE_CAP` 4 MiB** (`WEB_FILE_MIB` raises it).
- The shipped `input_map.json` and `default-font.json` are the maintainer's own.

## Things to know

- Browser storage keys are prefixed `anvil-of-splorr.`, but `playdeezgames.github.io` is one origin for all that user's project pages, so storage is shared with them. `about.html` says nothing there is private.
- No special headers are needed (no `SharedArrayBuffer`; the audio is an `AudioWorklet` fed through its message port).
- The page asks for `game_tags.json` at start; the 404 is harmless.
- Not checked: Firefox and touch screens.
