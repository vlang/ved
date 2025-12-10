// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import gg
import os
import time

const nr_elems_to_show_in_autocomplete = 12

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

fn (ved &Ved) draw_autocomplete_window() {
	max_col_len := 45
	cur_word := ved.word_under_cursor_no_right()
	// println('1DRAW WINDOW cur word="${cur_word}"')
	mut width := int(f64(ved.cfg.char_width * max_col_len) * 1.5)
	mut height := nr_elems_to_show_in_autocomplete * ved.cfg.line_height
	// Calculate position of the autocomplete box (next to the cursor)
	x := ved.calc_cursor_x()
	y := ved.calc_cursor_y() + ved.cfg.line_height

	if cur_word != '' && ved.autocomplete_info.vars.len == 0 {
		// Do not draw empty autocomplete window if there are no results and the user
		// started typing after `.`
		// println("NO RES, RET word='${cur_word}'")
		return
	}

	if ved.autocomplete_info.vars.len == 0 {
		return
	}
	ved.gg.draw_rect_filled(x, y, width, height, gg.white)
	// ved.gg.draw_text(x + 10, y + 30, 'AUTOCOMPLETE', txt_cfg)

	// for i, var in ved.autocomplete_info.vars {
	if ved.autocomplete_info.vars.len > 0 {
		var := ved.autocomplete_info.vars[0]
		// Calc max len of the first col to calculate first col width (to align second col)
		mut max_len := 0
		for field in var.fields {
			if field.name.len > max_len {
				max_len = field.name.len
			}
		}
		if max_len > max_col_len {
			max_len = max_col_len // + 4 // 4 - some spacing + space for ()
		}
		mut first_col_width := max_len * ved.cfg.char_width
		if first_col_width < 7 * ved.cfg.char_width {
			first_col_width = 7 * ved.cfg.char_width
		}

		// Draw var name + type
		nt := '${var.name}: ${var.typ}'
		ved.gg.draw_rect_filled(x + width, y, ved.cfg.char_width * nt.len, ved.cfg.line_height,
			gg.white)
		ved.gg.draw_text(x + width, y, nt, gg.TextCfg{
			...ved.cfg.txt_cfg
			bold: true
		})
		/*
		ved.gg.draw_rect(
			x: x + width
			y: y
			width: 100
			height: ved.cfg.line_height
			color: gg.white
		)
		*/
		mut i := 0 // number of filtered fields
		mut reached_bottom_edge := false
		for field in var.fields {
			if cur_word != '' && !field.name.to_lower().contains(cur_word.to_lower()) {
				continue
			}
			// Draw field name
			if !reached_bottom_edge {
				ved.gg.draw_text(x + 10, y + i * ved.cfg.line_height, field.name.limit(max_len),
					ved.cfg.txt_cfg)
				// Draw field type
				ved.gg.draw_text(x + 10 + first_col_width, y + i * ved.cfg.line_height,
					field.typ, gg.TextCfg{ ...ved.cfg.txt_cfg, color: gg.gray })
			}

			if i >= nr_elems_to_show_in_autocomplete - 1 {
				reached_bottom_edge = true
				// break
			}
			i++
		}

		// Draw number of fields and current number (e.g. "3/24")
		counter := '1/${i}'
		ved.gg.draw_text(x + width, y, counter, gg.TextCfg{
			...ved.cfg.txt_cfg
			align: .right
			color: gg.gray
		})
		// Draw time it took (debugging)
		ved.gg.draw_text(x + width, y + ved.cfg.line_height, ved.debug_info, gg.TextCfg{
			...ved.cfg.txt_cfg
			align: .right
			color: gg.green
		})
	}
}

fn (mut ved Ved) get_v_build_cmd() ?string {
	line_nr := ved.view.y + 1
	// file_name := os.base(ved.view.path)
	file_name := ved.view.path
	build_file := ved.get_build_file_location() or { return none }
	mut v_build_cmd := if build_file == '' { 'v .' } else { os.read_file(build_file) or {
			return none} }
	words := v_build_cmd.fields()
	mut dir_to_build := words[words.len - 1]
	module_name := get_module_name_from_file(ved.view.lines)
	if ved.view.path.contains('${module_name}/') {
		// dir_to_build = 'vlib/v/checker'
		dir_to_build = os.dir(ved.view.path)
	}
	// full_dir_to_build := os.join_path(ved.workspace, dir_to_build)
	full_dir_to_build := dir_to_build
	println('NNNdir_to_build="${full_dir_to_build}"')

	v_build_cmd = 'v -line-info "${file_name}:${line_nr}" ' + full_dir_to_build
	return v_build_cmd
}

// Calls `v -line-info "a.v:16" a.v`, parses output
fn (mut ved Ved) get_line_info() {
	ved.autocomplete_info.vars = []
	// cmd := 'v -line-info "${file_name}:${line_nr}" .' // ${ved.view.path}'
	v_build_cmd := ved.get_v_build_cmd() or { return }
	t := time.now()
	resp := os.execute(v_build_cmd) // or {
	time_diff := time.since(t)
	ved.debug_info = time_diff.str()
	// println('FAILED TO RUN V -line-info')
	// return
	//}
	println('v_build_cmd=')
	println(v_build_cmd)
	println('RESP=')
	println(resp.output)
	if resp.output.contains('not found among those parsed') {
	}
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

	for var_text in vars {
		if var_text == '' {
			continue
		}
		lines := var_text.trim_space().split('\n')
		if lines.len < 2 {
			continue
		}
		println('LINE 0')
		println(lines[0])
		mut var_line := lines[0]
		if !var_line.starts_with('VAR') {
			break
		}
		var_name_type_vals := var_line[3..].split(':')
		var_name, var_type := var_name_type_vals[0], var_name_type_vals[1]
		println('VARNAME=${var_name}')
		mut var := AutocompleteVar{
			name: var_name
			typ:  var_type
		}
		for i := 1; i < lines.len; i++ {
			vals := lines[i].split(':')
			if vals.len != 2 {
				continue
			}
			field_name := vals[0]
			field_type := vals[1]
			var.fields << AutocompleteField{field_name, field_type}
		}
		ved.autocomplete_info.vars << var
		// Now cache the type so that following lookups (pressing `.`) are instant
		ved.autocomplete_cache[var_type] = var.fields.clone()
	}
	// println(ved.autocomplete_info)
	ved.refresh = true
	ved.gg.refresh_ui()
	// exit(0)
}

// called when pressing Enter
fn (mut ved Ved) insert_suggested_field() {
	if unsafe { true } {
		return
	}
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

/*
fn (mut ved Ved) save_autocomplete_cache() {
}

fn (mut ved Ved) load_autocomplete_cache() {
}
*/

fn get_module_name_from_file(lines []string) string {
	for line in lines {
		if line.contains('module ') {
			return line.replace('module ', '').trim_space()
		}
	}
	return ''
}
