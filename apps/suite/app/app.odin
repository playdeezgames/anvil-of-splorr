// Selected with -collection:app=apps/suite (the default build): the main menu plus every editor.
package app

import cm "../../../common"
import gt "../../../gamepad_tester"
import launcher "../../../launcher"
import pe "../../../palette_editor"

editor: pe.Editor
tester: gt.Tester
entries: [2]launcher.Entry
menu: launcher.Launcher

make_tool :: proc() -> cm.Tool {
	editor = pe.editor_init()
	tester = gt.tester_init()
	entries = {
		{title = "PALETTE EDITOR", tool = pe.tool(&editor)},
		{title = "GAMEPAD TESTER", tool = gt.tool(&tester)},
	}
	menu = launcher.launcher_init("ANVIL OF SPLORR!!", entries[:])
	return launcher.tool(&menu)
}
