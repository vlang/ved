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

struct Debugger {
mut:
	p      os.Process
	output DebuggerOutput
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
	ved.debugger.send_cmd('b main__foo')
	ved.debugger.send_cmd('target stop-hook add --one-liner "frame variable"')
	ved.debugger.wait_for('Breakpoint ') or { panic(err) }

	ved.debugger.send_cmd('run')

	for {
		resp := ved.debugger.wait_for(' stop reason') or { break }
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

fn new_debugger(arg string) Debugger {
	mut d := Debugger{
		p: os.new_process(os.find_abs_path_of_executable('lldb') or { panic(err) })
	}
	d.p.set_args([arg])
	d.p.set_work_folder(os.getwd())
	d.p.set_redirect_stdio()
	return d
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

fn (mut d Debugger) parse_vars(s string, is_struct bool) DebuggerOutput {
	mut res := DebuggerOutput{}
	lines := s.split('\n')
	for line in lines {
		// Get variables: "(int) a = 3"
		if line.contains(' = ') && (is_struct || line.contains(') ')) { // structs don't contain (string)
			var := d.parse_var(line, s, is_struct)
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

fn (mut d Debugger) parse_var(line string, s string, is_struct bool) DebuggerVariable {
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
			parsed_struct := d.parse_vars(struct_code, true)
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

// "next" in lldb
fn (mut debugger Debugger) step_over() {
	debugger.send_cmd('next')

	for {
		resp := debugger.wait_for(' stop reason') or { break }
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
