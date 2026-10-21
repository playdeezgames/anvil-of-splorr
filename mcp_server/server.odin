// The Anvil as an MCP server: JSON-RPC 2.0 messages in, JSON-RPC replies out, with no I/O of its own
// except the world files its tools read and write (see the "world" tools in tools_world.odin). The
// stdio loop lives in ../anvil_mcp; everything here is testable by passing it message text.
//
// The server holds one open world (a `World` is ~21 MB, so it is on the heap) and edits the same model
// the editors use, so the editors' rules apply to an agent too. Nothing reaches disk until a tool
// saves, and a tool that would replace unsaved work refuses unless told to discard it.
package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

SERVER_NAME :: "anvil-of-splorr"
SERVER_VERSION :: "0.1.0"

// The protocol versions this server speaks; it answers `initialize` with the client's if listed, else
// with the newest.
@(rodata)
PROTOCOL_VERSIONS := [?]string{"2025-06-18", "2025-03-26", "2024-11-05"}

// JSON-RPC error codes.
ERR_PARSE :: -32700
ERR_INVALID_REQUEST :: -32600
ERR_METHOD_NOT_FOUND :: -32601
ERR_INVALID_PARAMS :: -32602

Server :: struct {
	world: ^cm.World, // always allocated; meaningful only while `open`
	open:  bool, // a world is loaded (opened or newly made)
	dirty: bool, // changed since it was last opened or saved (a new world counts as changed)
	file:  string, // the name the world was opened from / last saved to ("" = none); owned
	dir:   string, // the folder every file name is relative to; "" = the working directory
}

server_init :: proc(s: ^Server, dir: string) {
	s^ = {}
	s.world = new(cm.World)
	cm.world_reset(s.world)
	s.dir = strings.clone(dir)
}

server_destroy :: proc(s: ^Server) {
	free(s.world)
	delete(s.file)
	delete(s.dir)
	s^ = {}
}

// The text and kind of a tool's answer. Both are on the temp allocator.
Tool_Result :: struct {
	text:     string,
	is_error: bool,
}

Tool :: struct {
	name:        string,
	description: string,
	schema:      string, // the input schema, as JSON text
	run:         proc(s: ^Server, args: json.Object) -> Tool_Result,
}

ok_result :: proc(text: string) -> Tool_Result {
	return {text = text}
}

fail :: proc(text: string) -> Tool_Result {
	return {text = text, is_error = true}
}

// --- Messages ----------------------------------------------------------------------------------

// Handles one JSON-RPC message (without its trailing newline). Returns the reply text, or ok = false
// when there is nothing to send (a notification). All text is on the temp allocator.
handle_message :: proc(s: ^Server, message: []u8) -> (reply: string, ok: bool) {
	value, perr := json.parse(message, .JSON, false, context.temp_allocator)
	if perr != .None {
		return error_reply("null", ERR_PARSE, "parse error"), true
	}
	obj, is_obj := value.(json.Object)
	if !is_obj {
		return error_reply("null", ERR_INVALID_REQUEST, "a request is a JSON object"), true
	}
	id_value, has_id := obj["id"]
	id := "null"
	if has_id {
		id = id_text(id_value)
	}
	method, has_method := obj["method"].(json.String)
	if !has_method {
		// A response from the client (we send no requests) or nonsense: nothing to answer.
		return has_id ? error_reply(id, ERR_INVALID_REQUEST, "no method") : "", has_id
	}
	if !has_id {
		return "", false // a notification, such as notifications/initialized
	}
	params, _ := obj["params"].(json.Object)
	switch method {
	case "initialize":
		return result_reply(id, initialize_result(params)), true
	case "ping":
		return result_reply(id, "{}"), true
	case "tools/list":
		return result_reply(id, tools_list_result()), true
	case "tools/call":
		return handle_tool_call(s, id, params)
	}
	return error_reply(id, ERR_METHOD_NOT_FOUND, fmt.tprintf("unknown method %s", method)), true
}

initialize_result :: proc(params: json.Object) -> string {
	version := PROTOCOL_VERSIONS[0]
	if asked, ok := params["protocolVersion"].(json.String); ok {
		for v in PROTOCOL_VERSIONS {
			if v == asked {
				version = v
			}
		}
	}
	return fmt.tprintf(
		`{{"protocolVersion":%s,"capabilities":{{"tools":{{}}}},"serverInfo":{{"name":%s,"version":%s}}}}`,
		quote(version),
		quote(SERVER_NAME),
		quote(SERVER_VERSION),
	)
}

tools_list_result :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"tools":[`)
	for tool, i in tools() {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		fmt.sbprintf(&b, `{{"name":%s,"description":%s,"inputSchema":%s}}`, quote(tool.name), quote(tool.description), tool.schema)
	}
	strings.write_string(&b, "]}")
	return strings.to_string(b)
}

handle_tool_call :: proc(s: ^Server, id: string, params: json.Object) -> (reply: string, ok: bool) {
	name, has_name := params["name"].(json.String)
	if !has_name {
		return error_reply(id, ERR_INVALID_PARAMS, "a tool call needs a name"), true
	}
	args, _ := params["arguments"].(json.Object)
	for tool in tools() {
		if tool.name == name {
			res := tool.run(s, args)
			return result_reply(id, tool_result_json(res)), true
		}
	}
	return error_reply(id, ERR_INVALID_PARAMS, fmt.tprintf("unknown tool %s", name)), true
}

tool_result_json :: proc(r: Tool_Result) -> string {
	return fmt.tprintf(`{{"content":[{{"type":"text","text":%s}}],"isError":%v}}`, quote(r.text), r.is_error)
}

result_reply :: proc(id, result: string) -> string {
	return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":%s}}`, id, result)
}

error_reply :: proc(id: string, code: int, message: string) -> string {
	return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"error":{{"code":%d,"message":%s}}}}`, id, code, quote(message))
}

// A JSON string literal (quoted and escaped).
quote :: proc(text: string) -> string {
	out, _ := json.marshal(text, {}, context.temp_allocator)
	return string(out)
}

// A request id as it should be echoed: numbers that are whole print without a fraction.
id_text :: proc(v: json.Value) -> string {
	#partial switch x in v {
	case json.Float:
		if f64(i64(x)) == f64(x) {
			return fmt.tprintf("%d", i64(x))
		}
	}
	return to_json(v)
}

to_json :: proc(v: json.Value) -> string {
	out, err := json.marshal(v, {}, context.temp_allocator)
	return err == nil ? string(out) : "null"
}

// --- Arguments ---------------------------------------------------------------------------------

arg_string :: proc(args: json.Object, key: string) -> (value: string, ok: bool) {
	value, ok = args[key].(json.String)
	return
}

arg_bool :: proc(args: json.Object, key: string) -> bool {
	value, _ := args[key].(json.Boolean)
	return bool(value)
}
