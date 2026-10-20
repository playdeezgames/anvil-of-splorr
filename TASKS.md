# Tasks (from FINDINGS.md and the conversation)

Status: [x] done and committed, [~] done but not committed yet, [ ] to do.

## Image editor
- [x] Flip vertically, flip horizontally (Setup rows + FLIP H / FLIP V buttons)
- [x] Rotate 90 left / 90 right / 180 (width and height swap on a quarter turn)
- [x] Draw a framed rectangle, draw a filled rectangle (FRAME / FILL: keyboard corner placement, mouse drag)
- [x] Flood fill (4-connected region under the cursor, in the current colour)
- [x] Replace colour: every pixel of the colour under the cursor becomes the current colour
- [x] Clear: set the whole image to the current colour

## Glyph editor
- [x] Flip, rotate and rectangles, as in the image editor
- [x] Invert: every "on" pixel becomes "off" and vice versa

## Font editor
- [x] Flip the selected glyph (no rotation, by request)

## Whole suite
- [x] The editors' own text uses the hand-drawn default-font.json instead of the built-in 3x5 font

## Tileset editor (new tool)
- [x] A tileset is a list of images, each with a name; all images share one fixed width and height
- [x] Edit an image with the image editor's tools (reuse, not a copy)
- [x] 90 degree rotation is not offered when the tileset's width and height differ
- [x] Copy and paste images
- [x] Text entry keypad — done and wired to renaming
- [x] Rename an image (uses the keypad)
- [x] Add and delete images; file format (JSON, packed bytes); main menu entry; tests
