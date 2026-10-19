// Selected with -collection:app=apps/font_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import fe "../../../font_editor"

editor: fe.Editor // about 1 MB: a global, initialised in place

make_tool :: proc() -> cm.Tool {
	fe.editor_init(&editor)
	return fe.tool(&editor)
}
