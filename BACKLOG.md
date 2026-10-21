# Backlog

Not started; deliberately out of scope for the first milestone.

- Undo / redo for palette edits
- Import and export of other palette formats (e.g. GIMP `.gpl`, PNG strips)
- In-app editor for `input_map.json` (today it is edited by hand)
- World file size: 16 full-size tilesets (64x64, 256 images each) could reach tens of MB, far over the 4 MiB web file buffer. Decide on a lower tileset cap, a total tile-data cap, or a bigger buffer when the world file format is built
- Sound effects (USER_STORIES 5): up to 64 named sounds in the world file (short tone sequences), a sound editor reachable from the hub that plays on both frontends (SDL2 audio, web audio), and a runtime call to play a sound by name (the audio interface optional so games without sound still build). Deferred on purpose: it is the only story that needs new platform code and the demo game does not use it

Active work is tracked in `TASKS.md`.
