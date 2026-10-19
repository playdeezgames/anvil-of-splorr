// Selected with -collection:app=apps/glyph_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import ge "../../../glyph_editor"

editor: ge.Editor

make_tool :: proc() -> cm.Tool {
	editor = ge.editor_init()
	return ge.tool(&editor)
}
