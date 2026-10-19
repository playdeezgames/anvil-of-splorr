// Selected with -collection:app=apps/palette_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import pe "../../../palette_editor"

editor: pe.Editor

make_tool :: proc() -> cm.Tool {
	editor = pe.editor_init()
	return pe.tool(&editor)
}
