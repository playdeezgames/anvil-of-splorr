# Tasks (from FINDINGS.md and the conversation)

Status: [x] done and committed, [~] done but not committed yet, [ ] to do.

## Image editor
- [~] Flip vertically, flip horizontally (Setup rows + FLIP H / FLIP V buttons)
- [~] Rotate 90 left / 90 right / 180 (width and height swap on a quarter turn)
- [~] Draw a framed rectangle, draw a filled rectangle (FRAME / FILL: keyboard corner placement, mouse drag)
- [~] Flood fill (4-connected region under the cursor, in the current colour)
- [~] Replace colour: every pixel of the colour under the cursor becomes the current colour
- [~] Clear: set the whole image to the current colour

## Glyph editor
- [~] Flip, rotate and rectangles, as in the image editor
- [~] Invert: every "on" pixel becomes "off" and vice versa

## Font editor
- [~] Flip the selected glyph (no rotation, by request)

## Whole suite
- [ ] The editors' own text uses the hand-drawn default-font.json instead of the built-in 3x5 font
      (glyph height 6 instead of 5, real lower case, all printable characters; layouts need a pass)

## Tileset editor (new tool)
- [ ] A tileset is a list of images, each with a name; all images share one fixed width and height
- [ ] Edit an image with the image editor's tools (reuse, not a copy)
- [ ] 90 degree rotation is not offered when the tileset's width and height differ
- [ ] Copy and paste images
- [ ] Rename an image (needs a text-entry method that works with eight commands)
- [ ] Add and delete images; file format (JSON, packed bytes); main menu entry; tests
