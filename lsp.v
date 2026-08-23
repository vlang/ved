// lsp.v lets go_to_def (goto.v) resolve definitions via a real language
// server instead of grep without ever making grep worse: every failure mode
// here is caught and treated as "fall back to grep", never
// a crash or a stall.
module main

import os
import time
import x.json2

const lsp_request_timeout_ms = 2000

// spawned_lsp_processes tracks every LSP server child process for the
// lifetime of the ved process.
__global (
	spawned_lsp_processes    = []os.Process{}
	lsp_shutdown_hooks_armed = false
)

fn register_lsp_shutdown_hooks() {
	if lsp_shutdown_hooks_armed {
		return
	}
	lsp_shutdown_hooks_armed = true
	at_exit(kill_spawned_lsp_processes) or { eprintln('lsp: at_exit registration failed: ${err}') }
	exit_on_signal := fn (_ os.Signal) {
		exit(0)
	}
	os.signal_opt(.int, exit_on_signal) or {}
	os.signal_opt(.term, exit_on_signal) or {}
	os.signal_opt(.hup, exit_on_signal) or {}
}

fn kill_spawned_lsp_processes() {
	for mut p in spawned_lsp_processes {
		p.signal_term()
	}
}

// LspClient is a single spawned, initialized language server process.
struct LspClient {
mut:
	p                 os.Process
	next_id           int = 1
	root_uri          string
	position_encoding string = 'utf-16' // LSP default; upgraded to utf-8 if the server confirms support
	read_buf          string
}

// DefinitionLocation is the resolved target of a textDocument/definition req.
struct DefinitionLocation {
	uri       string
	line      int
	character int
}

// spawn_lsp_client starts command and performs the
// initialize/initialized handshake against root_uri. Returns an error
// so callers can fall back to grep.
fn spawn_lsp_client(command string, root_uri string) !LspClient {
	parts := command.split(' ').filter(it != '')
	if parts.len == 0 {
		return error('empty LSP server command')
	}
	exe := os.find_abs_path_of_executable(parts[0]) or {
		return error('LSP server "${parts[0]}" not found on PATH')
	}
	mut c := LspClient{
		p:        os.new_process(exe)
		root_uri: root_uri
	}
	if parts.len > 1 {
		c.p.set_args(parts[1..])
	}

	c.p.set_work_folder(uri_to_path(root_uri))
	c.p.set_redirect_stdio()
	c.p.run()
	register_lsp_shutdown_hooks()
	spawned_lsp_processes << c.p

	init_params := {
		'processId':    json2.Any(os.getpid())
		'rootUri':      json2.Any(root_uri)
		'capabilities': json2.Any({
			'general':      json2.Any({
				'positionEncodings': json2.Any([json2.Any('utf-8'), json2.Any('utf-16')])
			})
			'textDocument': json2.Any({
				'definition': json2.Any({
					'linkSupport': json2.Any(true)
				})
			})
		})
	}
	id := c.next_request_id()
	c.send_request(id, 'initialize', init_params)
	result := c.wait_for_result(id) or {
		stderr_out := c.p.stderr_slurp()
		c.p.signal_term()
		c.p.close()
		return error('initialize failed: ${err}${if stderr_out.len > 0 {
			' | stderr: ' + stderr_out
		} else {
			''
		}}')
	}
	result_map := result.as_map()
	caps := result_map['capabilities'] or { empty_any_map() }
	position_encoding := caps.as_map()['positionEncoding'] or { json2.Any('') }
	if position_encoding.str() == 'utf-8' {
		c.position_encoding = 'utf-8'
	}
	c.send_notification('initialized', map[string]json2.Any{})
	return c
}

fn empty_any_map() json2.Any {
	return json2.Any(map[string]json2.Any{})
}

fn (mut c LspClient) next_request_id() int {
	id := c.next_id
	c.next_id++
	return id
}

fn (mut c LspClient) send_request(id int, method string, params map[string]json2.Any) {
	c.write_message({
		'jsonrpc': json2.Any('2.0')
		'id':      json2.Any(id)
		'method':  json2.Any(method)
		'params':  json2.Any(params)
	})
}

fn (mut c LspClient) send_notification(method string, params map[string]json2.Any) {
	c.write_message({
		'jsonrpc': json2.Any('2.0')
		'method':  json2.Any(method)
		'params':  json2.Any(params)
	})
}

fn (mut c LspClient) write_message(msg map[string]json2.Any) {
	body := msg.str()
	c.p.stdin_write('Content-Length: ${body.len}\r\n\r\n${body}')
}

// read_message returns the next complete JSON-RPC message body, waiting up
// to timeout_ms.
fn (mut c LspClient) read_message(timeout_ms int) !string {
	deadline_ms := time.now().unix_milli() + i64(timeout_ms)
	for time.now().unix_milli() < deadline_ms {
		if !c.p.is_alive() {
			return error('LSP server process exited unexpectedly')
		}
		chunk := c.p.stdout_read()
		if chunk.len > 0 {
			c.read_buf += chunk
		}
		header_end := c.read_buf.index('\r\n\r\n') or {
			time.sleep(5 * time.millisecond)
			continue
		}
		header := c.read_buf[..header_end]
		mut content_length := 0
		for hline in header.split('\r\n') {
			if hline.to_lower().starts_with('content-length:') {
				content_length = hline.all_after(':').trim_space().int()
			}
		}
		body_start := header_end + 4
		if content_length <= 0 || c.read_buf.len < body_start + content_length {
			time.sleep(5 * time.millisecond)
			continue
		}
		body := c.read_buf[body_start..body_start + content_length]
		c.read_buf = c.read_buf[body_start + content_length..]
		return body
	}
	return error('LSP read timed out after ${timeout_ms}ms')
}

// wait_for_result reads messages until it finds the response matching id,
// silently dropping anything else.
fn (mut c LspClient) wait_for_result(id int) !json2.Any {
	start_ms := time.now().unix_milli()
	for {
		elapsed := int(time.now().unix_milli() - start_ms)
		remaining := lsp_request_timeout_ms - elapsed
		if remaining <= 0 {
			return error('response timed out waiting for id ${id}')
		}
		body := c.read_message(remaining)!
		msg := json2.decode[map[string]json2.Any](body) or { continue }
		msg_id := msg['id'] or { continue } // notification, not our response: keep waiting
		if msg_id.int() != id {
			continue // response to an earlier/unrelated request
		}
		err_val := msg['error'] or { json2.Any(json2.null) }
		if err_val !is json2.Null {
			err_msg := err_val.as_map()['message'] or { json2.Any('unknown LSP error') }
			return error(err_msg.str())
		}
		return msg['result'] or { json2.Any(json2.null) }
	}
	return error('unreachable') // the loop above only exits via return
}

fn (mut c LspClient) notify_did_open(uri string, language_id string, text string) {
	c.send_notification('textDocument/didOpen', {
		'textDocument': json2.Any({
			'uri':        json2.Any(uri)
			'languageId': json2.Any(language_id)
			'version':    json2.Any(1)
			'text':       json2.Any(text)
		})
	})
}

fn (mut c LspClient) notify_did_close(uri string) {
	c.send_notification('textDocument/didClose', {
		'textDocument': json2.Any({
			'uri': json2.Any(uri)
		})
	})
}

// request_definition sends textDocument/definition and parses the result
// which per spec may be null, a single Location, a Location[] or a
// LocationLink[]. Returns an error for all of those except a single/first
// Location(Link).
fn (mut c LspClient) request_definition(uri string, line int, character int) !DefinitionLocation {
	id := c.next_request_id()
	c.send_request(id, 'textDocument/definition', {
		'textDocument': json2.Any({
			'uri': json2.Any(uri)
		})
		'position':     json2.Any({
			'line':      json2.Any(line)
			'character': json2.Any(character)
		})
	})
	result := c.wait_for_result(id)!
	if result is json2.Null {
		return error('no definition found')
	}
	return parse_definition_result(result)
}

fn parse_definition_result(result json2.Any) !DefinitionLocation {
	mut candidate := result
	if result is []json2.Any {
		arr := result as []json2.Any
		if arr.len == 0 {
			return error('empty definition result')
		}
		candidate = arr[0]
	}
	m := candidate.as_map()
	// Location has uri+range; LocationLink has targetUri+
	// targetSelectionRange (falling back to targetRange).
	uri := m['uri'] or { m['targetUri'] or { json2.Any('') } }
	if uri.str() == '' {
		return error('definition result missing uri')
	}
	range_any := m['range'] or {
		m['targetSelectionRange'] or { m['targetRange'] or { empty_any_map() } }
	}
	start_any := range_any.as_map()['start'] or { empty_any_map() }
	start_map := start_any.as_map()
	return DefinitionLocation{
		uri:       uri.str()
		line:      (start_map['line'] or { json2.Any(0) }).int()
		character: (start_map['character'] or { json2.Any(0) }).int()
	}
}

fn language_id_for_ext(ext string) string {
	return match ext {
		'go' { 'go' }
		'rs' { 'rust' }
		'py' { 'python' }
		'v' { 'v' }
		else { ext }
	}
}

fn path_to_uri(path string) string {
	abs := if path.starts_with('/') { path } else { os.join_path(os.getwd(), path) }
	return 'file://${abs}'
}

fn uri_to_path(uri string) string {
	return uri.trim_string_left('file://')
}

// byte_col_to_lsp_character converts ved's byte offset column (see
// word_under_cursor in ved.v which indexes line the same way) into an
// LSP position, respecting whichever encoding the server negotiated.
fn byte_col_to_lsp_character(line string, byte_col int, encoding string) int {
	if encoding == 'utf-8' {
		return byte_col
	}
	mut utf16_units := 0
	mut bytes_seen := 0
	for r in line.runes() {
		if bytes_seen >= byte_col {
			break
		}
		bytes_seen += r.str().len
		utf16_units += if u32(r) > 0xFFFF { 2 } else { 1 }
	}
	return utf16_units
}

// lsp_character_to_byte_col is the inverse of byte_col_to_lsp_character, used
// to convert a definition target's position back into ved's byte column.
fn lsp_character_to_byte_col(line string, character int, encoding string) int {
	if encoding == 'utf-8' {
		return character
	}
	mut utf16_units := 0
	mut byte_pos := 0
	for r in line.runes() {
		if utf16_units >= character {
			break
		}
		byte_pos += r.str().len
		utf16_units += if u32(r) > 0xFFFF { 2 } else { 1 }
	}
	return byte_pos
}

fn (mut ved Ved) try_lsp_definition() bool {
	view := ved.view
	ext := os.file_ext(view.path).trim_string_left('.')
	if ext == '' || view.path == '' {
		return false
	}
	cmd := ved.cfg.lsp_servers[ext] or { return false }
	if cmd.trim_space() == '' {
		return false
	}

	mut client := ved.lsp_clients[ext] or {
		spawned := spawn_lsp_client(cmd, path_to_uri(ved.workspace)) or {
			eprintln('lsp: could not start server for .${ext}: ${err}')
			return false
		}
		spawned
	}
	// Persist any state the client accumulates back into the session cache
	// no matter how this function returns below.
	defer {
		ved.lsp_clients[ext] = client
	}

	uri := path_to_uri(view.path)
	text := view.lines.join('\n')
	client.notify_did_open(uri, language_id_for_ext(ext), text)

	cur_line := view.lines[view.y] or { '' }
	character := byte_col_to_lsp_character(cur_line, view.x, client.position_encoding)
	loc := client.request_definition(uri, view.y, character) or {
		client.notify_did_close(uri)
		eprintln('lsp: ${err}')
		return false
	}
	client.notify_did_close(uri)

	target_path := uri_to_path(loc.uri)
	if target_path != view.path {
		ved.view.open_file(target_path, loc.line)
	} else {
		ved.move_to_line(loc.line)
	}
	target_line := ved.view.lines[loc.line] or { '' }
	ved.view.x = lsp_character_to_byte_col(target_line, loc.character, client.position_encoding)
	return true
}
