// Selected with -collection:app=apps/suite (the default build): the main menu plus every editor.
package app

import cm "../../../common"
import ce "../../../controls_editor"
import fe "../../../font_editor"
import ge "../../../glyph_editor"
import ie "../../../image_editor"
import te "../../../tileset_editor"
import gt "../../../gamepad_tester"
import launcher "../../../launcher"
import pe "../../../palette_editor"
import we "../../../world_editor"

editor: pe.Editor
glyphs: ge.Editor
images: ie.Editor
tilesets: te.Editor // about 1 MB: a global, initialised in place
fonts: fe.Editor // about 1 MB: a global, initialised in place
worlds: we.Editor // about 20 MB (the world): a global, initialised in place
tester: gt.Tester
controls: ce.Editor
entries: [8]launcher.Entry
menu: launcher.Launcher

make_tool :: proc() -> cm.Tool {
	editor = pe.editor_init()
	glyphs = ge.editor_init()
	images = ie.editor_init()
	te.editor_init(&tilesets)
	fe.editor_init(&fonts)
	we.editor_init(&worlds)
	tester = gt.tester_init()
	controls = ce.editor_init()
	entries = {
		{title = "PALETTE EDITOR", tool = pe.tool(&editor)},
		{title = "IMAGE EDITOR", tool = ie.tool(&images)},
		{title = "TILESET EDITOR", tool = te.tool(&tilesets)},
		{title = "WORLD EDITOR", tool = we.tool(&worlds)},
		{title = "GLYPH EDITOR", tool = ge.tool(&glyphs)},
		{title = "FONT EDITOR", tool = fe.tool(&fonts)},
		{title = "CONTROLS", tool = ce.tool(&controls)},
		{title = "GAMEPAD TESTER", tool = gt.tool(&tester)},
	}
	menu = launcher.launcher_init("ANVIL OF SPLORR!!", entries[:])
	return launcher.tool(&menu)
}
