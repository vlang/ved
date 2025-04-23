// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

// This file contains logic related to running external commands (building projects,
// running files, running zsh commands)
import os

fn (mut ved Ved) build_app1() {
	ved.build_app('')
	// ved.next_split()
	// glfw.post_empty_event()
	// ved.prev_split()
	// glfw.post_empty_event()
	// ved.refresh = false
}

fn (mut ved Ved) build_app2() {
	ved.build_app('2')
}

fn (mut ved Ved) build_app(extra string) {
	eprintln('build_app: ${extra}')
	ved.is_building = true
	// Save each open file before building
	ved.save_changed_files()
	os.chdir(ved.workspace) or { return }
	dir := ved.workspace
	mut build_file := ved.get_build_file_location() or { return }
	if extra != '' {
		build_file += extra
	}

	out_file := os.join_path(dir, 'out')
	building_cmd := 'sh ${build_file}'
	eprintln('building with `${building_cmd}` ...')

	last_view_idx := ved.last_view_idx()

	os.write_file(out_file, 'Building...') or { panic(err) }
	ved.views[last_view_idx].open_file(out_file, 0)

	out := os.execute(building_cmd)
	if out.exit_code == -1 {
		return
	}

	os.write_file(out_file, filter_ascii_colors(out.output)) or { panic(err) }
	ved.views[last_view_idx].open_file(out_file, 0)

	ved.views[last_view_idx].shift_g()
	// error line
	lines := out.output.split_into_lines()
	println('lines=${lines}')
	// lines := alines.filter(it.contains('.v:') || it.contains('.go:'))
	mut no_errors := true // !out.output.contains('error:')
	for line in lines {
		// no "warning:" in a line means it's an error
		if !line.contains('warning:') {
			no_errors = false
		}
	}
	println('no_errors=${no_errors}')
	mut i := 0
	for _, line in lines {
		if !line.contains('.v:') && !line.contains('.go:') {
			println('skip1 ${line}')
			i++
			continue
		}
		is_warning := line.contains('warning:')
		is_notice := line.contains('notice:')
		is_error := line.contains('error:')
		if !is_warning && !is_notice && !is_error {
			println('skip2 ${line}')
			i++
			continue
		}
		println('${i}, HANDLE E LINE ${line}')
		// Go to the next warning only if there are no errors.
		// This makes Ved go to errors before warnings.
		if is_error && ((!is_notice && !is_warning) || (is_warning && no_errors)
			|| (is_notice && no_errors)) {
			mut error_details := ''
			for i < lines.len - 1 {
				if lines[i].contains('Details') {
					error_details += lines[i]
					if i + 1 < lines.len {
						error_details += lines[i + 1]
						break
					}
				}
				i++
			}
			// next_line := if i < lines.len - 1 { lines[i + 1] } else { '' }
			ved.go_to_error(line, error_details)
			break
		}
	}
	ved.refresh = true
	ved.gg.refresh_ui()
	// ved.refresh = true
	// time.sleep(4) // delay is_building to prevent flickering in the right split
	ved.is_building = false
	// Move to the first line of the output in the last view, so that it's
	// always visible
	ved.views[last_view_idx].from = 0
	ved.views[last_view_idx].set_y(0)
	/*
	// Reopen files (they were formatted)
	for _view in ved.views {
		// ui.alert('reopening path')
		mut view := _view
		println(view.path)
		view.open_file(view.path)
	}
	*/
}

// Run file in current view (go run [file], v run [file], python [file] etc)
// Saves time for user since they don't have to define 'build' for every file
fn (mut ved Ved) run_file() {
	mut view := ved.view
	ved.error_line = ''
	ved.is_building = true
	// println('start file run')
	// Save the file before building
	if view.changed {
		view.save_file()
	}
	// go run /a/b/c.go
	// dir is "/a/b/"
	// cd to /a/b/
	// dir := ospath.dir(view.path)
	dir := os.dir(view.path)
	os.chdir(dir) or {}
	out := os.execute('v run ${view.path}')
	os.write_file('${dir}/out', out.output) or { panic(err) }
	// TODO COPYPASTA
	mut last_view := ved.get_last_view()
	last_view.open_file('${dir}/out', 0)
	last_view.shift_g()
	ved.is_building = false
	// error line
	lines := out.output.split_into_lines()
	for line in lines {
		if line.contains('.v:') || line.contains('.go:') {
			ved.go_to_error(line, '')
			break
		}
	}
	ved.refresh = true
	ved.gg.refresh_ui()
}

fn (ved &Ved) run_zsh() {
	text := ved.query
	dir := ved.workspace
	os.chdir(dir) or { return }
	res := os.execute('zsh -ic "source ~/.zshrc; ${text}" > ${dir}/out')
	if res.exit_code == -1 {
	}
	// TODO copypasted some code from build_app()
	// mut f2 := os.create('$dir/out') or { panic('fail') }
	// f2.writeln(out.output) or { panic(err) }
	// f2.close()
	mut last_view := ved.get_last_view()
	last_view.open_file('${dir}/out', 0)
}
