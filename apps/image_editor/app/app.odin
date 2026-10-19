// Selected with -collection:app=apps/image_editor; frontends `import "app:app"`.
package app

import cm "../../../common"
import ie "../../../image_editor"

editor: ie.Editor

make_tool :: proc() -> cm.Tool {
	editor = ie.editor_init()
	return ie.tool(&editor)
}
