# Backlog

Not started; deliberately out of scope for the first milestone.

- Undo / redo for palette edits
- Import and export of other palette formats (e.g. GIMP `.gpl`, PNG strips)
- In-app editor for `input_map.json` (today it is edited by hand)
- World file size in the editors: the web file buffer is 4 MiB by default and a world with many big tilesets (16 full-size 64x64 tilesets could reach tens of MB) can exceed it. A build can raise it (`WEB_FILE_MIB=<n> ./build.sh web`, documented at FILE_CAP in `frontends/web/web.odin`), and a shipped game avoids the buffer by embedding its world with `#load` or having the page fetch it (`WEB_FETCH=world.json`), so the game case is settled; what stays open is a lower tileset cap or smarter storage for editing huge worlds in the browser

Active work is tracked in `TASKS.md`.
