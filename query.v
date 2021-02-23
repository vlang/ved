// Copyright (c) 2019-2021 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gx

const (
	txt_cfg = gx.TextCfg{
		size: 18
	}
)

fn (mut ved Ved) load_git_tree() {
	ved.query = ''
	// Cache all git files
	mut dir := ved.workspace
	if dir == '' {
		dir = '.'
	}
	s := os.exec('git -C $dir ls-files') or { return }
	/*
	ved.all_git_files = []
	ved.all_git_files << ved.view.open_paths
	mut git_files := s.output.split_into_lines()
	git_files.sort_by_len()
	ved.all_git_files << git_files
	*/
	ved.all_git_files = s.output.split_into_lines()
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

fn (q QueryType) str() string {
	match q {
		.search { return 'find' }
		.ctrlp { return 'ctrl p (git files)' }
		.open { return 'open' }
		.open_workspace { return 'open workspace' }
		.cam { return 'git commit -am' }
		.ctrlj { return 'ctrl j (opened files)' }
		.task { return 'new task/activity' }
		.grep { return 'git grep' }
	}
	return ''
}

const (
	small_queries  = [int(QueryType.search), int(QueryType.cam), int(QueryType.open)] // , GREP]
	max_grep_lines = 20
	query_width    = 400
)

// Search, commit, open, ctrl p
fn (mut ved Ved) draw_query() {
	// println('DRAW Q type=$ved.query_type')
	mut width := query_width
	mut height := 360
	if int(ved.query_type) in small_queries {
		height = 70
	}
	if ved.query_type == .grep {
		width *= 2
		height *= 2
	} else if ved.query_type in [.ctrlp, .ctrlj] {
		height = 500
	}
	x := (ved.win_width - width) / 2
	y := (ved.win_height - height) / 2
	ved.gg.draw_rect(x, y, width, height, gx.white)
	// query window title
	ved.gg.draw_rect(x, y, width, ved.line_height, ved.cfg.title_color)
	ved.gg.draw_text(x + 10, y, ved.query_type.str(), ved.cfg.file_name_cfg)
	// query background
	ved.gg.draw_rect(0, 0, ved.win_width, ved.line_height, ved.cfg.title_color)
	mut q := ved.query
	if ved.query_type == QueryType.search || ved.query_type == QueryType.grep {
		q = ved.search_query
	}
	ved.gg.draw_text(x + 10, y + 30, q, txt_cfg)
	if ved.query_type == .ctrlp {
		ved.draw_ctrlp_files(x, y)
	} else if ved.query_type == .task {
		ved.draw_top_tasks(x, y)
	} else if ved.query_type == .grep {
		ved.draw_git_grep(x, y)
	} else if ved.query_type == .ctrlj {
		ved.draw_open_files(x, y)
	}
}

fn (mut ved Ved) draw_ctrlp_files(x int, y int) {
	mut j := 0
	for file_ in ved.all_git_files {
		if j == 15 {
			break
		}
		yy := y + 60 + 30 * j
		if j == ved.gg_pos {
			ved.gg.draw_rect(x, yy, query_width * 2, 30, ved.cfg.vcolor)
		}
		mut file := file_.to_lower()
		file = file.trim_space()
		if !file.contains(ved.query.to_lower()) {
			continue
		}
		ved.gg.draw_text(x + 10, yy, file, txt_cfg)
		j++
	}
}

// TODO merge with ctrlp_files
fn (mut ved Ved) draw_open_files(x int, y int) {
	mut j := 0
	println('draw open_files len=$ved.open_paths.len')
	for file_ in ved.open_paths[ved.workspace_idx] {
		if j == 15 {
			break
		}
		yy := y + 60 + 30 * j
		if j == ved.gg_pos {
			ved.gg.draw_rect(x, yy, query_width * 2, 30, ved.cfg.vcolor)
		}
		mut file := file_.to_lower()
		file = file.trim_space()
		println(file)
		if !file.contains(ved.query.to_lower()) {
			continue
		}
		ved.gg.draw_text(x + 10, yy, file, txt_cfg)
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
		ved.gg.draw_text(x + 10, y + 60 + 30 * j, task, txt_cfg)
		j++
	}
}

fn (mut ved Ved) draw_git_grep(x int, y int) {
	for i, line in ved.gg_lines {
		if i == max_grep_lines {
			break
		}
		pos := line.index(':') or { continue }
		path := line[..pos].limit(30)
		pos2 := line.index_after(':', pos + 1)
		if pos2 == -1 || pos2 >= line.len - 1 {
			continue
		}
		text := line[pos2 + 1..].trim_space().limit(70)
		yy := y + 60 + 30 * i
		if i == ved.gg_pos {
			ved.gg.draw_rect(x, yy, query_width * 2, 30, ved.cfg.vcolor)
		}
		line_nr := line[pos + 1..pos2]
		ved.gg.draw_text(x + 10, yy, path + ':$line_nr', txt_cfg)
		ved.gg.draw_text(x + 250, yy, text, txt_cfg)
	}
}

// Open file on enter
// fn input_enter(s string, ved * Ved) {
// if s != '' {
fn (mut ved Ved) ctrlp_open() {
	ved.gg_pos = -1
	// Open the first file in the list
	for file_ in ved.all_git_files {
		mut file := file_.to_lower()
		file = file.trim_space()
		if file.contains(ved.query.to_lower()) {
			mut path := file_.trim_space()
			mut space := ved.workspace
			if space == '' {
				space = '.'
			}
			path = '$space/$path'
			ved.view.open_file(path)
			break
		}
	}
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
			path = '$space/$path'
			ved.view.open_file(path)
			break
		}
	}
}

fn (mut ved Ved) git_grep() {
	ved.gg_pos = 0 // select the first result for faster switching to the right file =
	// (especially if there's only one result)
	s := os.exec('git -C "$ved.workspace" grep -n "$ved.search_query"') or { return }
	lines := s.output.split_into_lines()
	ved.gg_lines = []
	for line in lines {
		if line.contains('thirdparty/') {
			continue
		}
		ved.gg_lines << line
	}
}

fn (mut ved Ved) search(goback bool) {
	if ved.search_query == '' {
		return
	}
	mut view := ved.view
	mut passed := false
	mut to := view.lines.len
	mut di := 1
	if goback {
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
				view.y = i
			} else {
				ved.move_to_line(i)
			}
			view.x = pos
			break
		}
		// Haven't found it, try from the top
		if !goback && !passed && i == view.lines.len - 1 {
			i = 0
			passed = true
		}
		/*
		// Same, but for reverse search
		else if goback && !passed && i == 0 {
			i = view.lines.len - 1
			passed = true
		}
		*/
	}
}
