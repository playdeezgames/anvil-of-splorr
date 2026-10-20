// Selected with -collection:app=apps/world_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import we "../../../world_editor"

editor: we.Editor // about 20 MB (the world): a global, initialised in place

make_tool :: proc() -> cm.Tool {
	we.editor_init(&editor)
	return we.tool(&editor)
}
