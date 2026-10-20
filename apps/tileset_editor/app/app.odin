// Selected with -collection:app=apps/tileset_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import te "../../../tileset_editor"

editor: te.Editor // about 1 MB: a global, initialised in place

make_tool :: proc() -> cm.Tool {
	te.editor_init(&editor)
	return te.tool(&editor)
}
