// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main

// TODO rename to query.v once the order bug is fixed.

import os
import gx

const (
	txt_cfg = gx.TextCfg { size: 9 }
)

fn (mut vid Vid) load_git_tree() {
	vid.query = ''
	// Cache all git files
	mut dir := vid.workspace
	if dir == '' {
		dir = '.'
	}
	s := os.exec('git -C $dir ls-files') or { return }
	vid.all_git_files = s.output.split_into_lines()
	vid.all_git_files.sort_by_len()
}

fn (vid &Vid) load_all_tasks() {
/*
	mut rows := vid.timer.db.q_strings('select distinct name from tasks')
	for row in rows {
		t := row.vals[0]
		vid.top_tasks << t
	}
	println(vid.top_tasks)
*/
}

fn (vid &Vid) typ_to_str() string {
	typ := vid.query_type
	match typ {
	.search {
		return 'find'
	}
	.ctrlp {
		return 'ctrl p (git files)'
	}
	.open {
		return 'open'
	}
	.open_workspace {
		return 'open workspace'
	}
	.cam {
		return 'git commit -am'
	}
	.ctrlj {
		return 'ctrl j'
	}
	.task {
		return 'new task/activity'
	}
	.grep { return 'git grep'	}
	}
	return ''
}

const (
	small_queries = [int(QueryType.search), QueryType.cam, QueryType.open]// , GREP]
	max_grep_lines  = 20
	query_width    = 400
)

// Search, commit, open, ctrl p
fn (mut vid Vid) draw_query() {
	// println('DRAW Q type=$vid.query_type')
	mut width := query_width
	mut height := 360
	if int(vid.query_type) in small_queries {
		height = 70
	}
	if vid.query_type == .grep {
		width *= 2
		height *= 2
	}
	x := (vid.win_width - width) / 2
	y := (vid.win_height - height) / 2
	vid.vg.draw_rect(x, y, width, height, gx.white)
	// query window title
	vid.vg.draw_rect(x, y, width, vid.line_height, vid.cfg.title_color)
	vid.vg.draw_text(x + 10, y, vid.typ_to_str(), vid.cfg.file_name_cfg)
	// query background
	vid.vg.draw_rect(0, 0, vid.win_width, vid.line_height, vid.cfg.title_color)
	mut q := vid.query
	if vid.query_type == QueryType.search || vid.query_type == QueryType.grep {
		q = vid.search_query
	}
	vid.vg.draw_text(x + 10, y + 30, q, txt_cfg)
	if vid.query_type == .ctrlp {
		vid.draw_ctrlp_files(x, y)
	}
	else if vid.query_type == QueryType.task {
		vid.draw_top_tasks(x, y)
	}
	else if vid.query_type == QueryType.grep {
		vid.draw_git_grep(x, y)
	}
}

fn (mut vid Vid) draw_ctrlp_files(x, y int) {
	mut j := 0
	for file_ in vid.all_git_files {
		if j == 10 {
			break
		}
		mut file := file_.to_lower()
		file = file.trim_space()
		if !file.contains(vid.query.to_lower()) {
			continue
		}
		vid.vg.draw_text(x + 10, y + 60 + 30 * j, file, txt_cfg)
		j++
	}
}

fn (mut vid Vid) draw_top_tasks(x, y int) {
	mut j := 0
	q := vid.query.to_lower()
	for task_ in vid.top_tasks {
		if j == 10 {
			break
		}
		task := task_.to_lower()
		if !task.contains(q) {
			continue
		}
		// println('DOES CONTAIN "$file" $j')
		vid.vg.draw_text(x + 10, y + 60 + 30 * j, task, txt_cfg)
		j++
	}
}

fn (mut vid Vid) draw_git_grep(x, y int) {
	for i, line in vid.gg_lines {
		if i == max_grep_lines {
			break
		}
		pos := line.index(':') or {
			continue
		}
		path := line[..pos].limit(30)
		pos2 := line.index_after(':', pos + 1)
		if pos2 == -1 || pos2 >= line.len - 1 {
			continue
		}
		text := line[pos2+1..].trim_space().limit(70)
		yy := y + 60 + 30 * i
		if i == vid.gg_pos {
			vid.vg.draw_rect(x, yy, query_width * 2, 30, vid.cfg.vcolor)
		}
		vid.vg.draw_text(x + 10, yy, path, txt_cfg)
		vid.vg.draw_text(x + 250, yy, text, txt_cfg)
	}
}

// Open file on enter
// fn input_enter(s string, vid * Vid) {
// if s != '' {
fn (mut vid Vid) ctrlp_open() {
	// Open the first file in the list
	for file_ in vid.all_git_files {
		mut file := file_.to_lower()
		file = file.trim_space()
		if file.contains(vid.query.to_lower()) {
			mut path := file_.trim_space()
			mut space := vid.workspace
			if space == '' {
				space = '.'
			}
			path = '$space/$path'
			vid.view.open_file(path)
			break
		}
	}
}

fn (mut vid Vid) git_grep() {
	vid.gg_pos = -1
	s := os.exec('git -C "$vid.workspace" grep -n "$vid.search_query"') or { return }
	lines := s.output.split_into_lines()
	vid.gg_lines = []
	for line in lines {
		if line.contains('thirdparty/') {
			continue
		}
		vid.gg_lines << line
	}
}

fn (mut vid Vid) search(goback bool) {
	if vid.search_query == '' {
		return
	}
	mut view := vid.view
	mut passed := false
	mut to := view.lines.len
	mut di := 1
	if goback {
		to = 0
		di = -1
	}
	for i := view.y;; i += di {
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
		if pos := line.index(vid.search_query) {
			// Already here, skip
			if pos == view.x && i == view.y {
				continue
			}
			// Found in current screen, dont move it
			if i >= view.from && i <= view.from + vid.page_height {
				view.y = i
			}
			else {
				vid.move_to_line(i)
			}
			view.x = pos
			break
		}
		// Haven't found it, try from the top
		if !passed && i == view.lines.len - 1 {
			i = 0
			passed = true
		}
	}
}

