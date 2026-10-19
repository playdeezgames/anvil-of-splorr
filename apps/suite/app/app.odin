// Selected with -collection:app=apps/suite (the default build): the main menu plus every editor.
package app

import cm "../../../common"
import fe "../../../font_editor"
import ge "../../../glyph_editor"
import ie "../../../image_editor"
import gt "../../../gamepad_tester"
import launcher "../../../launcher"
import pe "../../../palette_editor"

editor: pe.Editor
glyphs: ge.Editor
images: ie.Editor
fonts: fe.Editor // about 1 MB: a global, initialised in place
tester: gt.Tester
entries: [5]launcher.Entry
menu: launcher.Launcher

make_tool :: proc() -> cm.Tool {
	editor = pe.editor_init()
	glyphs = ge.editor_init()
	images = ie.editor_init()
	fe.editor_init(&fonts)
	tester = gt.tester_init()
	entries = {
		{title = "PALETTE EDITOR", tool = pe.tool(&editor)},
		{title = "IMAGE EDITOR", tool = ie.tool(&images)},
		{title = "GLYPH EDITOR", tool = ge.tool(&glyphs)},
		{title = "FONT EDITOR", tool = fe.tool(&fonts)},
		{title = "GAMEPAD TESTER", tool = gt.tool(&tester)},
	}
	menu = launcher.launcher_init("ANVIL OF SPLORR!!", entries[:])
	return launcher.tool(&menu)
}
