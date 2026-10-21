#+build !js
package mcp_server

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

new_server :: proc(dir: string) -> ^Server {
	s := new(Server)
	server_init(s, dir)
	return s
}

free_server :: proc(s: ^Server) {
	server_destroy(s)
	free(s)
	free_all(context.temp_allocator)
}

// Sends a request and parses the reply.
rpc :: proc(t: ^testing.T, s: ^Server, text: string) -> json.Object {
	reply, ok := handle_message(s, transmute([]u8)text)
	testing.expect(t, ok)
	v, err := json.parse(transmute([]u8)reply, .JSON, false, context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	obj, _ := v.(json.Object)
	return obj
}

// Calls a tool; returns the text it answered and whether it was an error.
call :: proc(t: ^testing.T, s: ^Server, name: string, args := "{}") -> (text: string, is_error: bool) {
	reply := rpc(t, s, fmt.tprintf(`{{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{{"name":%s,"arguments":%s}}}}`, quote(name), args))
	result, _ := reply["result"].(json.Object)
	content, _ := result["content"].(json.Array)
	testing.expect(t, len(content) == 1)
	first, _ := content[0].(json.Object)
	text, _ = first["text"].(json.String)
	is_error = bool(result["isError"].(json.Boolean))
	return
}

temp_dir :: proc(name: string) -> string {
	dir := fmt.tprintf("/tmp/anvil_mcp_test_%s", name)
	os.remove_all(dir)
	os.make_directory(dir)
	return dir
}

@(test)
test_initialize_lists_tools_and_ignores_notifications :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	reply := rpc(t, s, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}`)
	result, _ := reply["result"].(json.Object)
	testing.expect_value(t, result["protocolVersion"].(json.String), "2025-03-26")
	info, _ := result["serverInfo"].(json.Object)
	testing.expect_value(t, info["name"].(json.String), SERVER_NAME)
	_, ok := handle_message(s, transmute([]u8)string(`{"jsonrpc":"2.0","method":"notifications/initialized"}`))
	testing.expect(t, !ok)
	// An unknown version gets the newest.
	reply = rpc(t, s, `{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999"}}`)
	result, _ = reply["result"].(json.Object)
	testing.expect_value(t, result["protocolVersion"].(json.String), PROTOCOL_VERSIONS[0])
	testing.expect_value(t, reply["id"].(json.String), "a") // string ids are echoed
	raw, _ := handle_message(s, transmute([]u8)string(`{"jsonrpc":"2.0","id":42,"method":"ping"}`))
	testing.expect(t, strings.contains(raw, `"id":42,`)) // a whole-number id is echoed as written
	reply = rpc(t, s, `{"jsonrpc":"2.0","id":2,"method":"tools/list"}`)
	result, _ = reply["result"].(json.Object)
	list, _ := result["tools"].(json.Array)
	testing.expect_value(t, len(list), len(tools()))
	for entry, i in list {
		tool, _ := entry.(json.Object)
		testing.expect_value(t, tool["name"].(json.String), tools()[i].name)
		_, has_schema := tool["inputSchema"].(json.Object)
		testing.expectf(t, has_schema, "%s has a valid schema", tools()[i].name)
	}
}

@(test)
test_bad_requests_get_json_rpc_errors :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	code :: proc(t: ^testing.T, s: ^Server, text: string) -> int {
		reply := rpc(t, s, text)
		e, _ := reply["error"].(json.Object)
		return int(e["code"].(json.Float))
	}
	testing.expect_value(t, code(t, s, `nonsense`), ERR_PARSE)
	testing.expect_value(t, code(t, s, `[1]`), ERR_INVALID_REQUEST)
	testing.expect_value(t, code(t, s, `{"id":1,"method":"nope"}`), ERR_METHOD_NOT_FOUND)
	testing.expect_value(t, code(t, s, `{"id":1,"method":"tools/call","params":{}}`), ERR_INVALID_PARAMS)
	testing.expect_value(t, code(t, s, `{"id":1,"method":"tools/call","params":{"name":"nope"}}`), ERR_INVALID_PARAMS)
}

@(test)
test_world_tools_need_an_open_world :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	for name in ([]string{"world_save", "world_summary", "world_check_game_tags"}) {
		_, bad := call(t, s, name)
		testing.expectf(t, bad, "%s without a world", name)
	}
}

@(test)
test_new_save_open_round_trip_and_unsaved_guard :: proc(t: ^testing.T) {
	dir := temp_dir("round_trip")
	s := new_server(dir)
	defer free_server(s)
	_, bad := call(t, s, "world_new")
	testing.expect(t, !bad && s.open && s.dirty)
	text, bad2 := call(t, s, "world_summary")
	testing.expect(t, !bad2 && strings.contains(text, `"unsaved_changes":true`) && strings.contains(text, `"tags":["solid"]`) && strings.contains(text, `"tile_width":16`))
	// A new world with unsaved changes is not thrown away without being told.
	_, bad = call(t, s, "world_new")
	testing.expect(t, bad)
	_, bad = call(t, s, "world_save") // no file yet
	testing.expect(t, bad)
	text, bad = call(t, s, "world_save", `{"path":"a.json"}`)
	testing.expectf(t, !bad && !s.dirty && s.file == "a.json", "save: %s", text)
	// Another existing file is not overwritten without overwrite; the current file may be saved again.
	_, bad = call(t, s, "world_new")
	testing.expect(t, !bad)
	_, bad = call(t, s, "world_save", `{"path":"a.json"}`)
	testing.expect(t, bad)
	_, bad = call(t, s, "world_save", `{"path":"a.json","overwrite":true}`)
	testing.expect(t, !bad)
	_, bad = call(t, s, "world_save")
	testing.expect(t, !bad)
	// Open it again (discard is not needed while clean).
	s.world.tile_w = 9
	s.dirty = true
	_, bad = call(t, s, "world_open", `{"path":"a.json"}`)
	testing.expect(t, bad && s.world.tile_w == 9) // refused, nothing replaced
	text, bad = call(t, s, "world_open", `{"path":"a.json","discard":true}`)
	testing.expectf(t, !bad && s.world.tile_w == 16 && !s.dirty, "open: %s", text)
}

@(test)
test_paths_stay_inside_the_folder_and_bad_files_change_nothing :: proc(t: ^testing.T) {
	dir := temp_dir("paths")
	s := new_server(dir)
	defer free_server(s)
	call(t, s, "world_new")
	for path in ([]string{"", "/etc/x.json", "../x.json", "a/../x.json", "x.txt", "c:x.json", "a\\b.json"}) {
		_, bad := call(t, s, "world_save", fmt.tprintf(`{{"path":%s}}`, quote(path)))
		testing.expectf(t, bad, "save to %q", path)
		_, bad = call(t, s, "world_open", fmt.tprintf(`{{"path":%s,"discard":true}}`, quote(path)))
		testing.expectf(t, bad, "open %q", path)
	}
	// A file that is not a world leaves the open world alone.
	_ = os.write_entire_file(fmt.tprintf("%s/junk.json", dir), transmute([]u8)string(`{"tile_width": "wide"}`))
	s.world.tile_w = 9
	_, bad := call(t, s, "world_open", `{"path":"junk.json","discard":true}`)
	testing.expect(t, bad && s.world.tile_w == 9 && s.dirty)
	_, bad = call(t, s, "world_open", `{"path":"missing.json","discard":true}`)
	testing.expect(t, bad)
}

@(test)
test_game_tags_are_checked_from_text_or_a_file :: proc(t: ^testing.T) {
	dir := temp_dir("game_tags")
	s := new_server(dir)
	defer free_server(s)
	call(t, s, "world_new")
	text, bad := call(t, s, "world_check_game_tags", `{"text":"{\"tags\":[\"solid\",\"thing\",{\"name\":\"spawn\"}]}"}`)
	testing.expectf(t, !bad && strings.contains(text, `"needed":3`) && strings.contains(text, `"missing":["thing","spawn"]`), "got %s", text)
	_ = os.write_entire_file(fmt.tprintf("%s/game_tags.json", dir), transmute([]u8)string(`{"tags":["solid"]}`))
	text, bad = call(t, s, "world_check_game_tags", `{"path":"game_tags.json"}`)
	testing.expect(t, !bad && strings.contains(text, `"missing":[]`))
	_, bad = call(t, s, "world_check_game_tags", `{"text":"nonsense"}`)
	testing.expect(t, bad)
	_, bad = call(t, s, "world_check_game_tags")
	testing.expect(t, bad)
}

@(test)
test_the_shipped_demo_world_opens :: proc(t: ^testing.T) {
	s := new_server("anvil_runtime/testdata") // (tests run from the repo root)
	defer free_server(s)
	text, bad := call(t, s, "world_open", `{"path":"demo_world.json"}`)
	testing.expectf(t, !bad, "%s", text)
	text, bad = call(t, s, "world_summary")
	testing.expect(t, !bad && strings.contains(text, `"maps":[`) && strings.contains(text, `"unsaved_changes":false`))
}

@(test)
test_a_session_can_find_and_get_the_worlds_it_saved :: proc(t: ^testing.T) {
	dir := temp_dir("find")
	game := temp_dir("find_game")
	s := new_server(dir)
	defer free_server(s)
	text, bad := call(t, s, "world_list")
	testing.expect(t, !bad && strings.contains(text, `"files":[]`) && strings.contains(text, dir), text)
	call(t, s, "world_new")
	call(t, s, "tile_size_set", `{"width":5,"height":6}`)
	// Saving says where the file really is.
	text, bad = call(t, s, "world_save", `{"path":"mine.json"}`)
	testing.expect(t, !bad && strings.contains(text, fmt.tprintf(`"path":"%s/mine.json"`, dir)), text)
	text, _ = call(t, s, "world_list")
	testing.expect(t, strings.contains(text, `"name":"mine.json"`) && strings.contains(text, `"current":"mine.json"`), text)
	// Another folder: export with an absolute path (refusing a second time without overwrite).
	target := fmt.tprintf(`{{"path":"%s/world.json"}}`, game)
	text, bad = call(t, s, "world_export", target)
	testing.expect(t, !bad && strings.contains(text, fmt.tprintf(`%s/world.json`, game)), text)
	_, bad = call(t, s, "world_export", target)
	testing.expect(t, bad)
	_, bad = call(t, s, "world_export", fmt.tprintf(`{{"path":"%s/world.json","overwrite":true}}`, game))
	testing.expect(t, !bad)
	_, bad = call(t, s, "world_export", `{"path":"/nonexistent_folder_x/world.json"}`)
	testing.expect(t, bad)
	_, bad = call(t, s, "world_export", `{"path":"/tmp/../etc/w.json"}`)
	testing.expect(t, bad)
	_, bad = call(t, s, "world_save", fmt.tprintf(`{{"path":"%s/other.json"}}`, game)) // save stays inside the folder
	testing.expect(t, bad)
	// The exported file is a world a game can load, and another session can open it by path.
	s2 := new_server(dir)
	defer free_server(s2)
	text, bad = call(t, s2, "world_open", fmt.tprintf(`{{"path":"%s/world.json"}}`, game))
	testing.expect(t, !bad && s2.world.tile_w == 5 && s2.world.tile_h == 6, text)
	// world_read hands the text over in chunks.
	text, bad = call(t, s2, "world_read", `{"offset":0,"length":40}`)
	testing.expect(t, !bad && strings.contains(text, `"offset":0,"next":40,"done":false`) && strings.contains(text, `tile_width`), text)
	whole := strings.builder_make(context.temp_allocator)
	offset := 0
	for {
		chunk, bad2 := call(t, s2, "world_read", fmt.tprintf(`{{"path":"%s/world.json","offset":%d,"length":50}}`, game, offset))
		testing.expect(t, !bad2)
		v, _ := json.parse(transmute([]u8)chunk, .JSON, false, context.temp_allocator)
		obj, _ := v.(json.Object)
		part, _ := obj["text"].(json.String)
		strings.write_string(&whole, string(part))
		next, _ := arg_int(obj, "next")
		if bool(obj["done"].(json.Boolean)) {
			break
		}
		offset = next
	}
	testing.expect(t, strings.contains(strings.to_string(whole), `"tile_width": 5`))
	_, bad = call(t, s2, "world_read", `{"path":"missing.json"}`)
	testing.expect(t, bad)
}
