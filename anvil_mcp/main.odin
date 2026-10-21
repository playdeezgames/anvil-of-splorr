// With --tools it prints the tool reference (Markdown) and exits.
//
// Runs the Anvil as an MCP server over stdio: one JSON-RPC message per line on stdin, one reply per
// line on stdout (diagnostics go to stderr). Usage: anvil_mcp [--dir <folder>]; file names the tools
// take are relative to that folder (default: the working directory).
//
//     claude mcp add anvil -- ./build/anvil_mcp --dir worlds
package main

import mcp "../mcp_server"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"

// The longest message accepted (one line); a world's pixels can make requests large.
MAX_MESSAGE :: 16 << 20

main :: proc() {
	dir := ""
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		if args[i] == "--tools" {
			fmt.print(mcp.tool_reference_markdown())
			return
		}
		if args[i] == "--dir" && i + 1 < len(args) {
			dir = args[i + 1]
			i += 1
		} else {
			fmt.eprintfln("usage: anvil_mcp [--dir <folder>] | --tools")
			os.exit(2)
		}
	}
	server: mcp.Server
	mcp.server_init(&server, dir)

	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, os.to_stream(os.stdin), make([]u8, MAX_MESSAGE))
	for {
		line, err := bufio.reader_read_slice(&reader, '\n')
		if len(line) > 0 {
			if reply, ok := mcp.handle_message(&server, line); ok {
				fmt.println(reply)
			}
			free_all(context.temp_allocator)
		}
		if err != nil {
			if err == .Buffer_Full {
				fmt.eprintfln("message longer than %d bytes", MAX_MESSAGE)
			}
			break
		}
	}
	mcp.server_destroy(&server)
}
