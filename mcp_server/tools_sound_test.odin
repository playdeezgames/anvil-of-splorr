#+build !js
package mcp_server

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// Calls a sound tool that returns audio; gives the text and the decoded WAV bytes.
call_audio :: proc(t: ^testing.T, s: ^Server, name, args: string) -> (text: string, wav: []u8) {
	reply := rpc(t, s, fmt.tprintf(`{{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{{"name":%s,"arguments":%s}}}}`, quote(name), args))
	result, _ := reply["result"].(json.Object)
	content, _ := result["content"].(json.Array)
	if !testing.expectf(t, len(content) == 2, "%s gave %d content items", name, len(content)) {
		return
	}
	first, _ := content[0].(json.Object)
	text, _ = first["text"].(json.String)
	second, _ := content[1].(json.Object)
	testing.expect_value(t, second["type"].(json.String), "audio")
	testing.expect_value(t, second["mimeType"].(json.String), "audio/wav")
	data, _ := second["data"].(json.String)
	bytes, err := base64.decode(string(data), allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	return text, bytes
}

@(test)
test_sound_tools_store_check_and_render_play_text :: proc(t: ^testing.T) {
	dir := temp_dir("sound")
	s := new_server(dir)
	defer free_server(s)
	// Checking needs no world.
	text := good(t, s, "sound_check", `{"text":"T120 O4 L8 C D E P8 G4."}`)
	testing.expect(t, strings.contains(text, `"valid":true`) && strings.contains(text, `"notes":5`) && strings.contains(text, `"seconds":1.750`), text)
	text = good(t, s, "sound_check", `{"text":"C X"}`)
	testing.expect(t, strings.contains(text, `"valid":false,"position":2`), text)
	_, wav := call_audio(t, s, "sound_render", `{"text":"O3 A"}`) // no world needed for text either
	testing.expect(t, len(wav) == 44 + 2 * 11025 && string(wav[0:4]) == "RIFF", "half a second of audio")

	good(t, s, "world_new", "{}")
	good(t, s, "sound_new", `{"name":"pickup","text":"T200 O5 L16 C E G >C"}`)
	good(t, s, "sound_new", `{"name":"theme","text":"L8 CDEFGAB>C","loop":true}`)
	refused(t, s, "sound_new", `{"name":"pickup","text":"C"}`)
	refused(t, s, "sound_new", `{"name":"bad","text":"C X"}`)
	refused(t, s, "sound_new", `{"name":"bad","text":"C\nD"}`)
	refused(t, s, "sound_new", `{"name":"","text":"C"}`)
	testing.expect_value(t, s.world.sound_count, 2) // the refused ones added nothing
	text = good(t, s, "sound_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"pickup","loop":false,"seconds":`) && strings.contains(text, `"name":"theme","loop":true`), text)
	text = good(t, s, "sound_get", `{"name":"theme"}`)
	testing.expect(t, strings.contains(text, `"text":"L8 CDEFGAB>C"`) && strings.contains(text, `"notes":8`), text)
	good(t, s, "sound_set", `{"name":"theme","new_name":"music","text":"L4 CDEF","loop":false}`)
	refused(t, s, "sound_set", `{"name":"music","text":"Q"}`)
	refused(t, s, "sound_set", `{"name":"music","new_name":"pickup"}`)
	refused(t, s, "sound_set", `{"name":"nope","loop":true}`)
	text = good(t, s, "sound_get", `{"name":"music"}`)
	testing.expect(t, strings.contains(text, `"text":"L4 CDEF"`) && strings.contains(text, `"loop":false`), text) // the refused ones changed nothing
	testing.expect(t, strings.contains(good(t, s, "world_summary", "{}"), `"sounds":["pickup","music"]`))

	// Rendering a stored sound: the WAV carries exactly its length.
	text, wav = call_audio(t, s, "sound_render", `{"name":"music"}`)
	testing.expect(t, len(wav) == 44 + 2 * 2 * 22050, "four quarter notes at T120 are two seconds") // 4 * 0.5 s
	testing.expect(t, strings.contains(text, `"seconds":2.000`) && strings.contains(text, `"rate":22050`), text)
	refused(t, s, "sound_render", `{"name":"music","text":"C"}`) // exactly one of them
	refused(t, s, "sound_render", `{}`)
	refused(t, s, "sound_render", `{"text":""}`) // no notes
	refused(t, s, "sound_render", `{"text":"L1 T32 C C C C C"}`) // 37.5 s: too long to send inline
	// Export to a file.
	good(t, s, "sound_export", `{"name":"pickup","path":"pickup.wav"}`)
	refused(t, s, "sound_export", `{"name":"pickup","path":"pickup.wav"}`)
	good(t, s, "sound_export", `{"name":"pickup","path":"pickup.wav","overwrite":true}`)
	refused(t, s, "sound_export", `{"name":"pickup","path":"pickup.json"}`)
	refused(t, s, "sound_export", `{"name":"pickup","path":"../x.wav"}`)
	data, err := os.read_entire_file(fmt.tprintf("%s/pickup.wav", dir), context.temp_allocator)
	testing.expect(t, err == nil && len(data) > 44 && string(data[0:4]) == "RIFF")
	good(t, s, "sound_export", fmt.tprintf(`{{"text":"C","path":"%s/abs.wav"}}`, dir))
	// Sounds survive a save and an open.
	good(t, s, "world_save", `{"path":"s.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"s.json"}`)
	text = good(t, s2, "sound_get", `{"name":"pickup"}`)
	testing.expect(t, strings.contains(text, `T200 O5 L16 C E G >C`), text)
	good(t, s2, "sound_delete", `{"name":"pickup"}`)
	refused(t, s2, "sound_delete", `{"name":"pickup"}`)
	testing.expect_value(t, s2.world.sound_count, 1)
}
