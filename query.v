// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gx
import time
import gg

/*
const txt_cfg = gx.TextCfg{
	size: 18
}
*/

enum QueryType {
	ctrlp            = 0
	search           = 1
	cam              = 2
	open             = 3
	ctrlj            = 4
	task             = 5
	grep             = 6
	open_workspace   = 7
	run              = 8
	alert            = 9 // e.g. "running git pull..."
	search_in_folder = 10
}

fn (mut ved Ved) key_query(key gg.KeyCode, super bool) {
	match key {
		.backspace {
			ved.gg_pos = -1
			ved.just_switched = true
			if ved.query_type != .search && ved.query_type != .grep {
				if ved.query.len == 0 {
					return
				}
				ved.query = ved.query[..ved.query.len - 1]
			} else {
				if ved.search_query.len == 0 {
					return
				}
				ved.search_query = ved.search_query[..ved.search_query.len - 1]
			}
			return
		}
		.enter {
			match ved.query_type {
				.ctrlp {
					ved.ctrlp_open()
				}
				.ctrlj {
					ved.ctrlj_open()
				}
				.cam {
					ved.git_commit()
				}
				.open {
					ved.view.open_file(ved.query, 0)
				}
				.task {
					ved.insert_task() or {}
					if !ved.timer.pom_is_started && !ved.cur_task.starts_with('@') {
						// Start pomodoro with a new task if it's not already running
						ved.timer.pom_start = time.now().unix()
						ved.timer.pom_is_started = true
					}
					ved.cur_task = ved.query
					ved.task_start_unix = time.now().unix()
					ved.save_timer()
				}
				.run {
					ved.run_zsh()
				}
				.grep {
					// Key down was pressed after typing, now pressing enter opens the file
					if ved.gg_pos > -1 && ved.gg_lines.len > 0 {
						line := ved.gg_lines[ved.gg_pos]
						path := line.all_before(':')
						pos := line.index(':') or { 0 }
						pos2 := line.index_after(':', pos + 1) or { -1 }
						// line_nr := line[path.len + 1..].int() - 1
						line_nr := line[pos + 1..pos2].int() - 1
						ved.view.open_file(ved.workspace + '/' + path, line_nr)
						// ved.view.move_to_line(line_nr)
						ved.view.zz()
						ved.mode = .normal
					} else {
						// Otherwise just do a git grep on a submitted query
						ved.git_grep()
					}
					return
				}
				else {
					// println('CALLING SEARCH ON ENTER squery=$ved.search_query')
					ved.search(.forward)
				}
			}
			ved.mode = .normal
			return
		}
		.escape {
			ved.mode = .normal
			return
		}
		.down {
			if ved.mode == .query {
				match ved.query_type {
					.grep {
						// Going thru git grep results
						ved.gg_pos++
						if ved.gg_pos >= ved.gg_lines.len {
							ved.gg_pos = ved.gg_lines.len - 1
						}
					}
					.ctrlp {
						ved.gg_pos++
						if ved.gg_pos >= ved.all_git_files.len {
							ved.gg_pos = ved.all_git_files.len - 1
						}
					}
					.search {
						if ved.search_history.len > 0 {
							// History search
							ved.search_idx++
							if ved.search_idx >= ved.search_history.len {
								ved.search_idx = ved.search_history.len - 1
							}
							ved.search_query = ved.search_history[ved.search_idx]
						}
					}
					else {}
				}
			}
		}
		.up {
			if ved.mode == .query {
				match ved.query_type {
					.grep, .ctrlp {
						ved.gg_pos--
						if ved.gg_pos < 0 {
							ved.gg_pos = 0
						}
					}
					.search {
						if ved.search_history.len > 0 {
							ved.search_idx--
							if ved.search_idx < 0 {
								ved.search_idx = 0
							}
							ved.search_query = ved.search_history[ved.search_idx]
						}
					}
					else {}
				}
			}
		}
		.tab {
			// TODO COPY PASTA
			if ved.mode == .query && ved.query_type == .grep {
				ved.gg_pos++
			}
			ved.just_switched = true
		}
		.v {
			if super {
				clip := ved.cb.paste()
				ved.query += clip
			}
		}
		else {}
	}
}

fn (mut ved Ved) char_query(s string) {
	if int(s[0]) < 32 {
		return
	}
	mut q := ved.query
	// println('char q(${s}) ${ved.query_type}')
	if ved.query_type in [.search, .search_in_folder, .grep] {
		q = ved.search_query
		ved.search_query = q + s
		println('new sq=${ved.search_query}')
	} else {
		ved.query = q + s
	}
}

fn (mut ved Ved) load_git_tree() {
	ved.query = ''

	mut dir := ved.workspace
	if dir == '' {
		dir = '.'
	}
	if ved.is_git_tree() {
		// Cache all git files
		s := os.execute('git -C ${dir} ls-files')
		if s.exit_code == -1 {
			return
		}
		ved.all_git_files = s.output.split_into_lines()
	} else {
		// Get all files if not a git repo
		mut files := []string{}
		os.walk_with_context(dir, &files, fn (mut fs []string, f string) {
			if f == '.' || f == '..' {
				return
			}
			if os.is_file(f) {
				fs << f
			}
		})

		ved.all_git_files = []
		for f in files {
			ved.all_git_files << f.all_after('${dir}/')
		}
	}
	/*
	ved.all_git_files = []
	ved.all_git_files << ved.view.open_paths
	mut git_files := s.output.split_into_lines()
	git_files.sort_by_len()
	ved.all_git_files << git_files
	*/
	ved.all_git_files.sort_by_len()
}

fn (ved &Ved) load_all_tasks() {
	/*
	mut rows := ved.timer.db.q_strings('select distinct name from tasks')
	for row in rows {
		t := row.vals[0]
		ved.top_tasks << t
	}
	println(ved.top_tasks)
	*/
}

fn (mut ved Ved) is_git_tree() bool {
	path := if ved.workspace == '' { '.' } else { ved.workspace }

	out := os.execute('git -C "${path}" rev-parse --is-inside-work-tree')
	if out.exit_code != -1 {
		return out.output == 'true\n'
	}

	return false
}

fn (q QueryType) str() string {
	return match q {
		.search { 'find' }
		.search_in_folder { 'find in folder' }
		.ctrlp { 'ctrl p (git files)' }
		.open { 'open' }
		.open_workspace { 'open workspace' }
		.cam { 'git commit -am' }
		.ctrlj { 'ctrl j (opened files)' }
		.task { 'new task/activity' }
		.grep { 'git grep' }
		.run { 'run a zsh command' }
		.alert { '' }
	}
}

const small_queries = [QueryType.search, .cam, .open, .run, .alert] //.grep

const max_grep_lines = 20
const query_width = 700

// Search, commit, open, ctrl p
fn (mut ved Ved) draw_query() {
	// println('DRAW Q type=$ved.query_type')
	mut width := query_width
	mut height := 360
	if ved.query_type in small_queries {
		height = 70
	}
	if ved.query_type == .grep {
		width *= 2
		height *= 2
	} else if ved.query_type in [.ctrlp, .ctrlj] {
		height = (max_grep_lines + 2) * (ved.cfg.line_height + line_padding) + 15
	}
	x := (ved.win_width - width) / 2
	y := (ved.win_height - height) / 2
	ved.gg.draw_rect_filled(x, y, width, height, gx.white)
	// query window title
	ved.gg.draw_rect_filled(x, y, width, ved.cfg.line_height, ved.cfg.title_color)
	ved.gg.draw_text(x + 10, y, ved.query_type.str(), ved.cfg.file_name_cfg)
	// query background
	ved.gg.draw_rect_filled(0, 0, ved.win_width, ved.cfg.line_height, ved.cfg.title_color)
	query_to_draw := if ved.query_type in [.search, .search_in_folder, .grep] {
		ved.search_query
	} else {
		ved.query
	}

	ved.gg.draw_text(x + 10, y + ved.cfg.line_height, query_to_draw, ved.cfg.txt_cfg)
	// Draw cursor
	cursor_x := x + 10 + query_to_draw.len * ved.cfg.char_width + 1 // cursor
	cursor_y := y + ved.cfg.line_height + 2
	ved.gg.draw_rect(x: cursor_x, y: cursor_y, w: 2, h: ved.cfg.line_height - 4)
	// Draw separator between query and files
	if ved.query_type !in [.search, .cam, .run] {
		ved.gg.draw_rect(
			x:     x
			y:     y + ved.cfg.line_height * 2
			w:     width
			h:     1
			color: ved.cfg.comment_color
		)
	}
	// Draw files
	ved.draw_query_files(ved.query_type, x, y)
}

const nr_ctrlp_results = 20
const line_padding = 5

fn (mut ved Ved) draw_query_files(kind QueryType, x int, y int) {
	mut j := 0
	lines := match kind {
		.ctrlp {
			ved.all_git_files
		}
		.grep {
			ved.gg_lines
		}
		.ctrlj {
			ved.open_paths[ved.workspace_idx]
		}
		else {
			[]string{}
		}
	}
	for s in lines {
		if j == nr_ctrlp_results {
			break
		}
		yy := y + 60 + (ved.cfg.line_height + line_padding) * j
		if j == ved.gg_pos {
			ved.gg.draw_rect_filled(x, yy, query_width, 30, ved.cfg.vcolor)
		}
		match kind {
			.grep {
				pos := s.index(':') or { continue }
				path := s[..pos].limit(55)
				pos2 := s.index_after(':', pos + 1) or { -1 }
				if pos2 == -1 || pos2 >= s.len - 1 {
					continue
				}
				text := s[pos2 + 1..].trim_space().limit(100)
				if j == ved.gg_pos {
					ved.gg.draw_rect_filled(x, yy, query_width * 3, 30, ved.cfg.vcolor)
				}
				line_nr := s[pos + 1..pos2]
				ved.gg.draw_text2(
					x:     x + 10
					y:     yy
					text:  path.limit(50) + ':${line_nr}'
					color: gx.purple
				)
				ved.gg.draw_text(x + ved.cfg.char_width * 45, yy, text, ved.cfg.txt_cfg)
			}
			.ctrlp, .ctrlj {
				mut file := s.to_lower()
				file = file.trim_space()
				if !file.contains(ved.query.to_lower()) {
					continue
				}
				ved.gg.draw_text(x + 10, yy, file, ved.cfg.txt_cfg)
			}
			else {}
		}

		j++
	}
}

/*
fn (mut ved Ved) draw_ctrlp_files(x int, y int) {
	mut j := 0
	for file_ in ved.all_git_files {
		if j == nr_ctrlp_results {
			break
		}
		yy := y + 60 + (ved.cfg.line_height + 5) * j
		if j == ved.gg_pos {
			ved.gg.draw_rect_filled(x, yy, query_width, 30, ved.cfg.vcolor)
		}
		mut file := file_.to_lower()
		file = file.trim_space()
		if !file.contains(ved.query.to_lower()) {
			continue
		}
		ved.gg.draw_text(x + 10, yy, file, ved.cfg.txt_cfg)
		j++
	}
}

// TODO merge with ctrlp_files
fn (mut ved Ved) draw_open_files(x int, y int) {
	mut j := 0
	// println('draw open_files len=$ved.open_paths.len')
	for file_ in ved.open_paths[ved.workspace_idx] {
		if j == 15 {
			break
		}
		yy := y + 60 + 30 * j
		if j == ved.gg_pos {
			ved.gg.draw_rect_filled(x, yy, query_width * 2, 30, ved.cfg.vcolor)
		}
		mut file := file_.to_lower()
		file = file.trim_space()
		if !file.contains(ved.query.to_lower()) {
			continue
		}
		ved.gg.draw_text(x + 10, yy, file, ved.cfg.txt_cfg)
		j++
	}
}

fn (mut ved Ved) draw_top_tasks(x int, y int) {
	mut j := 0
	q := ved.query.to_lower()
	for task_ in ved.top_tasks {
		if j == 10 {
			break
		}
		task := task_.to_lower()
		if !task.contains(q) {
			continue
		}
		// println('DOES CONTAIN "$file" $j')
		ved.gg.draw_text(x + 10, y + 60 + 30 * j, task, ved.cfg.txt_cfg)
		j++
	}
}
*/

/*
fn (mut ved Ved) draw_git_grep(x int, y int) {
	for i, line in ved.gg_lines {
		if i == max_grep_lines {
			break
		}
		pos := line.index(':') or { continue }
		path := line[..pos].limit(50)
		pos2 := line.index_after(':', pos + 1) or { -1 }
		if pos2 == -1 || pos2 >= line.len - 1 {
			continue
		}
		text := line[pos2 + 1..].trim_space().limit(70)
		yy := y + 60 + 30 * i
		if i == ved.gg_pos {
			ved.gg.draw_rect_filled(x, yy, query_width * 3, 30, ved.cfg.vcolor)
		}
		line_nr := line[pos + 1..pos2]
		ved.gg.draw_text(x + 10, yy, path.limit(50) + ':${line_nr}', ved.cfg.txt_cfg)
		ved.gg.draw_text(x + 450, yy, text, ved.cfg.txt_cfg)
	}
}
*/

// Open file on enter
// fn input_enter(s string, ved * Ved) {
// if s != '' {
fn (mut ved Ved) ctrlp_open() {
	// Open the selected file in the list
	mut i := 0
	for file_ in ved.all_git_files {
		mut file := file_.to_lower()
		file = file.trim_space()
		if file.contains(ved.query.to_lower()) {
			if i == ved.gg_pos || ved.gg_pos <= 0 {
				mut path := file_.trim_space()
				mut space := ved.workspace
				if space == '' {
					space = '.'
				}
				path = '${space}/${path}'
				ved.view.open_file(path, 0)
				break
			}
			i++
		}
	}
	ved.gg_pos = -1
	ved.save_session()
}

// TODO merge with fn above
fn (mut ved Ved) ctrlj_open() {
	for p in ved.open_paths[ved.workspace_idx] {
		if p.contains(ved.query.to_lower()) {
			mut path := p.trim_space()
			mut space := ved.workspace
			if space == '' {
				space = '.'
			}
			path = '${space}/${path}'
			ved.view.open_file(path, 0)
			break
		}
	}
}

fn (mut ved Ved) git_grep() {
	ved.gg_pos = 0 // select the first result for faster switching to the right file =
	// (especially if there's only one result)
	query := ved.search_query.replace('$', '\\\$')
	s := os.execute('git -C "${ved.workspace}" grep -F -n "${query}"')
	if s.exit_code == -1 {
		return
	}
	lines := s.output.split_into_lines()
	ved.gg_lines = []
	top_loop: for line in lines {
		if line.contains('thirdparty/') {
			continue
		}
		if line.contains('LICENSE:') {
			continue
		}
		if line.contains('Binary file ') && line.contains(' matches') {
			continue
		}
		// Handle grep file extensions to filter (defined in .ved file per workspace)
		if ved.grep_file_exts[ved.workspace].len > 0 {
			for ext in ved.grep_file_exts[ved.workspace] {
				if !line.contains('.${ext}:') {
					continue top_loop
				}
			}
		}
		ved.gg_lines << line
	}
}

enum SearchType {
	backward
	forward
}

fn (mut ved Ved) search(search_type SearchType) {
	println('search() query=${ved.search_query}')
	if ved.search_query == '' {
		return
	}
	mut view := ved.view
	mut passed := false
	mut to := view.lines.len
	mut di := 1
	goback := search_type == .backward
	if search_type == .backward {
		to = 0
		di = -1
	}
	for i := view.y; true; i += di {
		if goback && i <= to {
			break
		}
		if !goback && i >= to {
			break
		}
		if i >= view.lines.len {
			break
		}
		if i < 0 {
			continue
		}
		line := view.lines[i]
		if pos := line.index(ved.search_query) {
			// Already here, skip
			if pos == view.x && i == view.y {
				continue
			}
			// Found in current screen, dont move it
			if i >= view.from && i <= view.from + ved.page_height {
				ved.prev_y = view.y
				view.set_y(i)
			} else {
				ved.move_to_line(i)
			}
			view.x = pos
			break
		}
		// Haven't found it, try from the top
		if !goback && !passed && i == view.lines.len - 1 {
			if ved.search_dir == '' {
				i = 0
				passed = true
			} else {
				// Go to the next file in the directory
				ext := '.' + ved.view.path.after('.')
				files := os.walk_ext(os.dir(ved.view.path), ext)
				for ved.search_dir_idx < files.len {
					text := os.read_file(files[ved.search_dir_idx]) or { panic(err) }
					if text.contains(ved.search_query) {
						ved.view.open_file(files[ved.search_dir_idx], 0)
						ved.view.gg()
						ved.search_dir_idx++
						ved.search(search_type)
						break
					}
					ved.search_dir_idx++
				}
				// println('ffffff $files')
			}
		}
		/*
		// Same, but for reverse search
		else if goback && !passed && i == 0 {
			i = view.lines.len - 1
			passed = true
		}
		*/
	}
	ved.search_history << ved.search_query
	// ved.search_idx++
	ved.search_idx = ved.search_history.len
}
