// Copyright (c) 2019-2023 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import term
import time
import gg
import strings

const breakpoint_color = gg.rgb(136, 136, 97) // yellow

const debugger_name_color = gg.rgb(197, 134, 192) // pink

enum DebuggerBackend {
	lldb
	gdb
}

struct Debugger {
mut:
	p       os.Process
	output  DebuggerOutput
	backend DebuggerBackend
}

struct DebuggerOutput {
mut:
	vars []DebuggerVariable

	line_nr int // line at which "->" points
}

struct DebuggerVariable {
	name string
	typ  string
mut:
	value string
}

fn (mut ved Ved) run_debugger(breakpoints []int) {
	if !ved.view.path.ends_with('.v') {
		println('Debugger only works with V files for now')
		return
	}
	os.system('v -w -g -o /tmp/a ${ved.view.path}')
	ved.debugger = new_debugger('/tmp/a')
	ved.debugger.run()

	for breakpoint in breakpoints {
		_ = breakpoint
		// view.debugger.send_cmd('b main__foo')
	}
	match ved.debugger.backend {
		.lldb {
			ved.debugger.send_cmd('b main__foo')
			ved.debugger.send_cmd('target stop-hook add --one-liner "frame variable"')
		}
		.gdb {
			ved.debugger.send_cmd('set pagination off')
			ved.debugger.send_cmd('set width unlimited')
			ved.debugger.send_cmd('set confirm off')
			ved.debugger.send_cmd('break main__foo')
			// gdb has no direct equivalent of lldb's stop-hook, so a hook-stop
			// script is defined instead: it fires on every stop (breakpoint hit,
			// step, etc.) and prints the locals followed by a fixed marker,
			// giving us a reliable, backend agnostic point to resume parsing at.
			// The marker must come after info locals: gdb's echo flushes
			// independently of info locals 's output, so if it were first,
			// wait_for() could see the marker before the locals it's meant to
			// signal the end of.
			ved.debugger.send_cmd('define hook-stop')
			ved.debugger.send_cmd('info locals')
			ved.debugger.send_cmd('echo ${gdb_stop_marker}\\n')
			ved.debugger.send_cmd('end')
		}
	}
	ved.debugger.wait_for('Breakpoint ') or { panic(err) }

	ved.debugger.send_cmd('run')

	for {
		resp := ved.debugger.wait_for(ved.debugger.stop_marker()) or { break }
		time.sleep(100 * time.millisecond)
		// println('<<<<<<<<<<<<<<<<')
		// println(resp)
		// println('>>>>>>>>>>>>>>>>')
		ved.debugger.parse_output(resp)
		return
	}

	ved.debugger.p.close()
	ved.debugger.p.wait()
	dump(ved.debugger.p.code)
}

fn (mut d Debugger) send_cmd(cmd string) {
	eprintln(term.bright_yellow('\n\n> sending command: ${cmd}'))
	d.p.stdin_write('${cmd}\n')
}

fn (mut d Debugger) wait_for(what string) !string {
	mut sb := strings.new_builder(100)
	eprintln(term.bright_blue('> waiting for: ${what}'))
	// now := time.now()
	for d.p.is_alive() {
		line := d.p.stdout_read()
		// d.p.stderr_read()
		if line.len == 0 {
			continue
		}
		sb.write_string(line)
		eprint('line len: ${line.len:5} | ${line}')
		if line.contains(what) {
			return sb.str()
			// break
		}
		if line.contains('exited with status') {
			return error('process exited')
		}
	}
	return ''
}

const gdb_stop_marker = 'VED_DEBUGGER_STOPPED'

fn new_debugger(arg string) Debugger {
	backend, exe_path := find_debugger_backend()
	mut d := Debugger{
		p:       os.new_process(exe_path)
		backend: backend
	}
	d.p.set_args([arg])
	d.p.set_work_folder(os.getwd())
	d.p.set_redirect_stdio()
	return d
}

// find_debugger_backend picks lldb on macOS and gdb everywhere
// else, falling back to whichever of the two is actually installed.
fn find_debugger_backend() (DebuggerBackend, string) {
	$if macos {
		if path := os.find_abs_path_of_executable('lldb') {
			return DebuggerBackend.lldb, path
		}
		if path := os.find_abs_path_of_executable('gdb') {
			return DebuggerBackend.gdb, path
		}
	} $else {
		if path := os.find_abs_path_of_executable('gdb') {
			return DebuggerBackend.gdb, path
		}
		if path := os.find_abs_path_of_executable('lldb') {
			return DebuggerBackend.lldb, path
		}
	}
	panic('no debugger found, please install lldb or gdb')
}

fn (d Debugger) stop_marker() string {
	return match d.backend {
		.lldb { ' stop reason' }
		.gdb { gdb_stop_marker }
	}
}

fn (mut d Debugger) run() {
	d.p.run()
}

fn (mut view View) add_breakpoint(line_nr int) {
	view.breakpoints << line_nr
}

fn (mut d Debugger) parse_output(s string) {
	// d.output = d.parse_vars(s, false)
	d.add_output(d.parse_vars(s, false))
}

fn (mut d Debugger) parse_vars(s string, is_struct bool) DebuggerOutput {
	return match d.backend {
		.lldb { d.parse_vars_lldb(s, is_struct) }
		.gdb { d.parse_vars_gdb(s) }
	}
}

// merges old and new output, so that old vars are not lost and var positions are not changed (otherwise
// UI becomes jumpy)
fn (mut d Debugger) add_output(new_output DebuggerOutput) {
	loop1: for new_var in new_output.vars {
		for i, var in d.output.vars {
			// Update value
			if var.name == new_var.name {
				d.output.vars[i].value = new_var.value
				continue loop1
			}
		}
		// Add a new var to the end
		d.output.vars << new_var
	}
	d.output.line_nr = new_output.line_nr
}

fn (mut d Debugger) parse_vars_lldb(s string, is_struct bool) DebuggerOutput {
	mut res := DebuggerOutput{}
	lines := s.split('\n')
	for line in lines {
		// Get variables: "(int) a = 3"
		if line.contains(' = ') && (is_struct || line.contains(') ')) { // structs don't contain (string)
			var := d.parse_var_lldb(line, s, is_struct)
			if var.name != '' {
				res.vars << var
			}
		}
		// Get yellow line number
		else if line.starts_with('-> ') {
			// "-> 2   		str := 'hello'"
			vals := line.fields()
			res.line_nr = vals[1].int()
		}
	}
	// println('parse_vars res=')
	// println(res)
	return res
}

fn (mut d Debugger) parse_var_lldb(line string, s string, is_struct bool) DebuggerVariable {
	println('\n\nparse_var line=')
	println('"${line}"')
	par_pos := if is_struct { 0 } else { line.index(') ') or { 0 } }
	typ := if is_struct { '' } else { line[1..par_pos] }
	eq_pos := line.index(' = ') or { 0 }
	name := line[par_pos + 2..eq_pos]
	// Skip the var if it's no valid yet (not present in the code before the current line)
	backtrace := s.before('->').after('stop reason = ')
	println('BACKTRACE:')
	println(backtrace)
	println('____________________________')
	if !backtrace.contains(name) {
		println("SKIPPING ${name} for line '${line}'")
		return DebuggerVariable{}
	}
	mut value := line[eq_pos + 3..]
	// Get correct string value
	if typ == 'string' || (is_struct && value.contains('(str =')) {
		if value.contains('str = 0x0000000000000000') {
			value = "''"
		} else if value.contains('(str = "') {
			start := value.index('(str =') or { 0 }
			end := value.index(',') or { 0 }
			value = value[start + 6..end]
		}
		// Get array contents by callign Array_xxx_str() in lldb
	} else if typ.starts_with('Array_') {
		elem_type := typ.replace('Array_', '')
		d.send_cmd('p Array_${elem_type}_str(${name})')
		resp := d.wait_for('(string)') or { return DebuggerVariable{} }
		value = resp.after('(string)').after('= "').before('",')
	} else if typ == 'bool' {
		// Bool
		// (bool) bool1 = '\x01'  len=6 TRUE
		//(bool) bool2 = '\0' line=4 FALSE
		// println('BOOL=${value} len=${value.len}')
		// println(int(value[1]))
		if value.len == 6 {
			value = 'true'
		} else {
			value = 'false'
		}
	} else if typ.starts_with('_option_') {
		// Option
		d.send_cmd('p ${typ}_str(${name})')
		resp := d.wait_for('"') or { return DebuggerVariable{} }
		value = resp.after('(str = "').before('", ')
	} else if value == '{' {
		// Struct
		struct_code := s.after(line).before('\n}\n')
		println('STRUCT 1st line:')
		println(line)
		println('STRUCT code:')
		println(struct_code)
		println('============')
		// Sum types
		if struct_code.contains('_string =') {
			// value = 'sum t:${typ}'
			// d.send_cmd('p v_typeof_sumtype_${typ}(${name}._typ)')
			d.send_cmd('p ${typ}_str(${name})')
			resp := d.wait_for('"') or { return DebuggerVariable{} }
			value = resp.after('(str = "').before('", ')
		} else if struct_code.contains('_object') {
			// Interface
			d.send_cmd('p ${typ}_str(${name})')
			resp := d.wait_for('"') or { return DebuggerVariable{} }
			value = resp.after('(str = "').before('", ')
		} else {
			// Normal struct
			parsed_struct := d.parse_vars_lldb(struct_code, true)
			println('PARSED STRUCT: ${parsed_struct}')
			value = parsed_struct.format_struct()
		}
	}
	return DebuggerVariable{
		name:  name
		typ:   typ.replace('main__', '').replace('Array_', '[]').replace('_option_', '?').replace('__',
			'.')
		value: value.trim_space()
	}
}

// "next" in lldb and gdb
fn (mut debugger Debugger) step_over() {
	debugger.send_cmd('next')

	for {
		resp := debugger.wait_for(debugger.stop_marker()) or { break }
		time.sleep(100 * time.millisecond)
		// println('2<<<<<<<<<<<<<<<<')
		// println(resp)
		// println('2>>>>>>>>>>>>>>>>')
		debugger.parse_output(resp)
		// d.send_cmd('next')
		return
	}
}

fn (mut ved Ved) draw_debugger_variables() {
	split_from, split_to := ved.get_splits_from_to()
	split_width := ved.split_width()
	// We draw debugger variables in the last split (the one with the output)
	last_split_x := split_width * (split_to - 1 - split_from)
	// println('split_width=${split_width}, last_split_x=${last_split_x}')
	// println('DRAW D VARS x=${last_split_x} splitw=${split_width}, to=${split_to}, from=${split_from}')
	ved.gg.draw_rect_filled(last_split_x, ved.cfg.line_height, split_width, 500, ved.cfg.title_color)
	if ved.debugger.output.vars.len == 0 {
		return
	}
	x := last_split_x + 3
	// Calc first col width
	max_name_len := 20
	max_value_len := 45
	/*
	mut max_len := ved.debugger.output.vars[0].name.len
	for var in ved.debugger.output.vars {
		if var.name.len > max_len {
			max_len = var.name.len
		}
	}
	*/
	col_width := (max_name_len + 1) * ved.cfg.char_width
	// Draw the table
	for i, var in ved.debugger.output.vars {
		y := (i + 1) * ved.cfg.line_height + 3
		// col_width := 80
		ved.gg.draw_text(x, y, var.name.limit(max_name_len),
			color: debugger_name_color
			size:  ved.cfg.txt_cfg.size
		)
		ved.gg.draw_text(x + col_width, y, var.value_fmt(max_value_len),
			color: gg.white
			size:  ved.cfg.txt_cfg.size
		)
		ved.gg.draw_text(ved.win_width - col_width, y, var.typ,
			color: gg.white
			size:  ved.cfg.txt_cfg.size
		)
	}
}

fn (d DebuggerOutput) format_struct() string {
	mut sb := strings.new_builder(100)
	sb.write_string('{ ')
	for i, var in d.vars {
		sb.write_string(var.name)
		sb.write_string(': ')
		sb.write_string(var.value)
		if i < d.vars.len - 1 {
			sb.write_string(', ')
		}
	}
	sb.write_string(' }')
	return sb.str()
}

fn (d DebuggerVariable) value_fmt(max_len int) string {
	if d.value.len > max_len {
		return d.value.limit(max_len) + '...'
	}
	return d.value
}

// gdb backend
//
// gdb's info locals (auto-run on every stop via the hook-stop script set up
// in run_debugger()) prints one local per line as "name = value" with no
// type info and nested structs inlined as "{field = val, field = val}" on
// that same line. That's different enough from lldb's per line typed
// multi-line-struct "frame variable" output that it gets its own parser
// below, rather than being bolted onto parse_vars_lldb/parse_var_lldb.

fn (mut d Debugger) parse_vars_gdb(s string) DebuggerOutput {
	mut res := DebuggerOutput{}
	lines := s.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		// gdb echoes the current source line after every stop, e.g. "12\tx := 3"
		if trimmed.len > 0 && trimmed[0].is_digit() && trimmed.contains('\t') {
			num := trimmed.all_before('\t')
			if num.len > 0 && num.bytes().all(it.is_digit()) {
				res.line_nr = num.int()
			}
			continue
		}
		if line.contains(' = ') {
			var := d.parse_var_gdb(line, false)
			if var.name != '' {
				res.vars << var
			}
		}
	}
	return res
}

fn (mut d Debugger) parse_var_gdb(line string, is_nested bool) DebuggerVariable {
	eq_pos := line.index(' = ') or { return DebuggerVariable{} }
	name := line[..eq_pos].trim_space()
	if !is_valid_gdb_ident(name) {
		return DebuggerVariable{}
	}
	value := line[eq_pos + 3..].trim_space()
	if is_nested {
		return d.format_gdb_value_by_shape(name, value)
	}
	typ := d.gdb_whatis(name)
	return d.format_gdb_typed_value(name, typ, value)
}

// format_gdb_typed_value is used for top level locals where a "whatis" call
// gives us a real type name to dispatch on.
fn (mut d Debugger) format_gdb_typed_value(name string, typ string, value string) DebuggerVariable {
	if typ == 'string' {
		return DebuggerVariable{
			name:  name
			typ:   typ
			value: "'${extract_quoted(value)}'"
		}
	}
	if typ == 'unsigned char' && is_gdb_char_literal(value) {
		return DebuggerVariable{
			name:  name
			typ:   'bool'
			value: if value.starts_with('1') { 'true' } else { 'false' }
		}
	}
	if typ == 'array' && value.starts_with('{') {
		return DebuggerVariable{
			name:  name
			typ:   '[]'
			value: 'array (len=${extract_field(value, 'len')})'
		}
	}
	if typ.starts_with('_option_') {
		state := extract_field(value, 'state').trim_space().all_before(' ')
		return DebuggerVariable{
			name:  name
			typ:   typ
			value: if state == '0' { '<ok>' } else { '<none/err>' }
		}
	}
	if value.starts_with('{') {
		return DebuggerVariable{
			name:  name
			typ:   typ
			value: format_gdb_struct_fields(mut d, value)
		}
	}
	return DebuggerVariable{
		name:  name
		typ:   typ
		value: value
	}
}

// format_gdb_value_by_shape is used for fields nested inside a struct where
// querying "whatis" per field would mean one extra gdb round trip per field.
// It relies on the printed shape of the value alone which is enough to spot
// V strings/bools but not enough to specialize arrays or options.
fn (mut d Debugger) format_gdb_value_by_shape(name string, value string) DebuggerVariable {
	if value.starts_with('{') && value.contains('str = ') && value.contains('is_lit') {
		return DebuggerVariable{
			name:  name
			typ:   'string'
			value: "'${extract_quoted(value)}'"
		}
	}
	if is_gdb_char_literal(value) {
		return DebuggerVariable{
			name:  name
			typ:   'bool'
			value: if value.starts_with('1') { 'true' } else { 'false' }
		}
	}
	if value.starts_with('{') {
		return DebuggerVariable{
			name:  name
			typ:   ''
			value: format_gdb_struct_fields(mut d, value)
		}
	}
	return DebuggerVariable{
		name:  name
		typ:   ''
		value: value
	}
}

fn format_gdb_struct_fields(mut d Debugger, value string) string {
	inner := value[1..value.len - 1]
	fields := split_top_level(inner)
	mut parts := []string{}
	for field in fields {
		eq_pos := field.index(' = ') or { continue }
		fname := field[..eq_pos].trim_space()
		fval := field[eq_pos + 3..].trim_space()
		if !is_valid_gdb_ident(fname) {
			continue
		}
		sub := d.format_gdb_value_by_shape(fname, fval)
		parts << '${sub.name}: ${sub.value}'
	}
	return '{ ' + parts.join(', ') + ' }'
}

// gdb_whatis returns the type of "expr" (e.g. "int", "string", "_option_int")
// with the "struct " prefix gdb prints stripped off. Returns '' if gdb didn't
// answer before the process exited.
fn (mut d Debugger) gdb_whatis(expr string) string {
	d.send_cmd('whatis ${expr}')
	mut sb := strings.new_builder(100)
	for d.p.is_alive() {
		line := d.p.stdout_read()
		if line.len == 0 {
			continue
		}
		sb.write_string(line)
		acc := sb.str()
		if acc.contains('type = ') {
			mut typ := acc.all_after_last('type = ').all_before('\n').trim_space()
			if typ.starts_with('struct ') {
				typ = typ[7..]
			}
			return typ
		}
		if acc.contains('exited with status') {
			return ''
		}
	}
	return ''
}

// extract_quoted pulls the text between the first and last `"` in a gdb value
// string, e.g. `0x679f36 <L.726> "hello"` -> "hello". Doesn't attempt to
// unescape backslash sequences, same as the equivalent lldd side parsing.
fn extract_quoted(value string) string {
	start := value.index('"') or { return '' }
	end := value.last_index('"') or { return '' }
	if end <= start {
		return ''
	}
	return value[start + 1..end]
}

// extract_field pulls a "field = value" out of an inline gdb struct dump,
// e.g. extract_field('{data = 0x0, len = 3, cap = 3}', 'len') -> '3'.
fn extract_field(value string, field string) string {
	marker := '${field} = '
	idx := value.index(marker) or { return '?' }
	rest := value[idx + marker.len..]
	end := rest.index_any(',}')
	if end == -1 {
		return rest.trim_space()
	}
	return rest[..end].trim_space()
}

// split_top_level splits a comma separated list on commas that aren't nested
// inside braces/parens, e.g. "a = {x = 1}, b = 2" -> ["a = {x = 1}", " b = 2"].
fn split_top_level(s string) []string {
	mut parts := []string{}
	mut depth := 0
	mut start := 0
	for i := 0; i < s.len; i++ {
		c := s[i]
		if c == `{` || c == `(` {
			depth++
		} else if c == `}` || c == `)` {
			depth--
		} else if c == `,` && depth == 0 {
			parts << s[start..i]
			start = i + 1
		}
	}
	if start < s.len {
		parts << s[start..]
	}
	return parts
}

fn is_valid_gdb_ident(name string) bool {
	if name.len == 0 {
		return false
	}
	if !(name[0].is_letter() || name[0] == `_`) {
		return false
	}
	for c in name {
		if !(c.is_letter() || c.is_digit() || c == `_`) {
			return false
		}
	}
	return true
}

fn is_gdb_char_literal(value string) bool {
	return (value.starts_with('0 ') || value.starts_with('1 ')) && value.contains("'")
}
