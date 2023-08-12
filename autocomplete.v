module main

import gx
import os

const nr_elems_to_show_in_autocomplete = 12

fn (ved &Ved) draw_autocomplete_window() {
	if ved.autocomplete_info.vars.len == 0 {
		return
	}
	cur_word := ved.word_under_cursor_no_right()
	println('1DRAW WINDOW cur word="${cur_word}"')
	mut width := query_width
	mut height := nr_elems_to_show_in_autocomplete * ved.cfg.line_height // 360
	// Calculate position of the autocomplete box (next to the cursor)
	x := ved.calc_cursor_x()
	y := ved.calc_cursor_y() + ved.cfg.line_height

	ved.gg.draw_rect_filled(x, y, width, height, gx.white)
	ved.gg.draw_rect_filled(0, 0, ved.win_width, ved.cfg.line_height, ved.cfg.title_color)
	// ved.gg.draw_text(x + 10, y + 30, 'AUTOCOMPLETE', txt_cfg)

	// for i, var in ved.autocomplete_info.vars {
	if ved.autocomplete_info.vars.len > 0 {
		var := ved.autocomplete_info.vars[0]
		mut i := 0
		for field in var.fields {
			if !field.name.to_lower().contains(cur_word.to_lower()) {
				continue
			}
			ved.gg.draw_text(x + 10, y + i * ved.cfg.line_height, field.name, ved.cfg.txt_cfg)
			if i >= nr_elems_to_show_in_autocomplete - 1 {
				break
			}
			i++
		}
	}
}

struct AutocompleteInfo {
mut:
	vars []AutocompleteVar
}

struct AutocompleteVar {
	name string
	typ  string
mut:
	fields []AutocompleteField
}

struct AutocompleteField {
	name string
	typ  string
}

fn (mut ved Ved) get_v_build_cmd() ?string {
	line_nr := ved.view.y + 1
	file_name := os.base(ved.view.path)
	build_file := ved.get_build_file_location() or { return none }
	mut v_build_cmd := if build_file == '' { 'v .' } else { os.read_file(build_file) or {
			return none
		} }
	words := v_build_cmd.fields()
	dir_to_build := os.join_path(ved.workspace, words[words.len - 1])
	println('dir_to_build=${dir_to_build}')
	v_build_cmd = 'v -line-info "${file_name}:${line_nr}" ' + v_build_cmd[2..]
	return v_build_cmd
}

// Calls `v -line-info "a.v:16" a.v`, parses output
fn (mut ved Ved) get_line_info() {
	// cmd := 'v -line-info "${file_name}:${line_nr}" .' // ${ved.view.path}'
	v_build_cmd := ved.get_v_build_cmd() or { return }
	resp := os.execute(v_build_cmd) // or {
	// println('FAILED TO RUN V -line-info')
	// return
	//}
	println('v_build_cmd=')
	println(v_build_cmd)
	println('RESP=')
	println(resp.output)
	// Parse the format
	/*
	===
	VAR cmd:string
	str:u8
	len:int
	is_lit:int
	===
	*/
	mut vars := resp.output.split('===')
	if vars.len == 0 {
		println('no vars text')
		return
	}
	println('VARS=')
	println(vars)

	// ved.autocomplete_info.vars = []

	for var_text in vars {
		if var_text == '' {
			continue
		}
		lines := var_text.trim_space().split('\n')
		println('LINE 0')
		println(lines[0])
		mut var_name := lines[0]
		if !var_name.starts_with('VAR') {
			break
		}
		var_name = var_name[3..]
		println('VARNAME=${var_name}')
		mut var := AutocompleteVar{
			name: var_name
		}
		for i := 1; i < lines.len; i++ {
			vals := lines[i].split(':')
			field_name := vals[0]
			field_type := vals[1]
			var.fields << AutocompleteField{field_name, field_type}
		}
		ved.autocomplete_info.vars << var
	}
	println(ved.autocomplete_info)
	// exit(0)
}

// called when pressing Enter
fn (mut ved Ved) insert_suggested_field() {
	if ved.autocomplete_info.vars.len == 0 {
		return
	}
	var := ved.autocomplete_info.vars[0]
	if var.fields.len == 0 {
		return
	}
	cur_word := ved.word_under_cursor_no_right()
	for field in var.fields {
		if !field.name.to_lower().contains(cur_word.to_lower()) {
			continue
		}
		ved.view.x--
		ved.view.db(false)
		ved.view.insert_text(field.name)
		ved.view.delete_char() // TODO extra unneeded char for some reason, improve db() algo instead
		break
		// if i >= nr_elems_to_show_in_autocomplete - 1 {
		// break
		//}
	}
	ved.mode = .insert
}
