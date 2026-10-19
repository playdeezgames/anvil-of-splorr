// Writes the built-in editor font as a font file: `./build.sh builtin-font` (output:
// build/builtin-font.json). The repo's default-font.json is hand drawn and is never written by this.
package main

import cm "../../common"
import "core:fmt"
import "core:os"

main :: proc() {
	path := len(os.args) > 1 ? os.args[1] : "build/builtin-font.json"
	f := new(cm.Pixel_Font) // about 1 MB: not on the stack
	cm.pixel_font_load_builtin(f)
	text := cm.pixel_font_to_json(f, context.allocator)
	if err := os.write_entire_file(path, text); err != nil {
		fmt.eprintfln("could not write %s: %v", path, err)
		os.exit(1)
	}
	defined, total := cm.pixel_font_coverage(f)
	fmt.printfln("wrote %s (height %d, printable %d/%d)", path, f.height, defined, total)
}
