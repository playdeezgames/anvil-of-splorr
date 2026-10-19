// Selected with -collection:app=apps/gamepad_tester; frontends `import "app:app"`.
package app

import cm "../../../common"
import gt "../../../gamepad_tester"

tester: gt.Tester

make_tool :: proc() -> cm.Tool {
	tester = gt.tester_init()
	return gt.tool(&tester)
}
