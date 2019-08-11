// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main

// TODO rename to query.v once the order bug is fixed. 

import os 
import gx 

const (
	txt_cfg = gx.TextCfg { size: 25 }
)

fn (ctx mut Vid) load_git_tree() {
	ctx.query = ''
	// Cache all git files
	mut dir := ctx.workspace
	if dir == '' {
		dir = '.'
	}
	s := os.exec('git -C $dir ls-files') or { return }
	ctx.all_git_files = s.split_into_lines()
	ctx.all_git_files.sort_by_len()
}

fn (ctx mut Vid) load_all_tasks() {
/* 
	mut rows := ctx.timer.db.q_strings('select distinct name from tasks')
	for row in rows {
		t := row.vals[0]
		ctx.top_tasks << t
	}
	println(ctx.top_tasks)
*/ 
}

fn (ctx &Vid) typ_to_str() string {
	typ := ctx.query_type
	switch typ {
	case SEARCH:
		return 'find'
	case CTRLP:
		return 'ctrl p'
	case OPEN:
		return 'open'
	case CAM:
		return 'git commit -am'
	case CTRLJ:
		return 'ctrl j'
	case TASK:
		return 'new task/activity'
	case GREP: return 'git grep'
	}
	return ''
}

const (
	small_queries = [SEARCH, CAM, OPEN]// , GREP]
	MaxGrepLines  = 20
	QueryWidth    = 400
)

// Search, commit, open, ctrl p
fn (ctx &Vid) draw_query() {
	// println('DRAW Q type=$ctx.query_type')
	mut width := QueryWidth
	mut height := 360
	if ctx.query_type in small_queries {
		height = 70
	}
	if ctx.query_type == GREP {
		width *= 2
		height *= 2
	}
	x := (ctx.win_width - width) / 2
	y := (ctx.win_height - height) / 2
	ctx.vg.draw_rect(x, y, width, height, gx.White)
	// query window title
	ctx.vg.draw_rect(x, y, width, ctx.line_height, ctx.cfg.title_color)
	ctx.ft.draw_text(x + 10, y, ctx.typ_to_str(), ctx.cfg.file_name_cfg)
	// query background
	ctx.vg.draw_rect(0, 0, ctx.win_width, ctx.line_height, ctx.cfg.title_color)
	mut q := ctx.query
	if ctx.query_type == SEARCH || ctx.query_type == GREP {
		q = ctx.search_query
	}
	ctx.ft.draw_text(x + 10, y + 30, q, txt_cfg)
	if ctx.query_type == CTRLP {
		ctx.draw_ctrlp_files(x, y)
	}
	else if ctx.query_type == TASK {
		ctx.draw_top_tasks(x, y)
	}
	else if ctx.query_type == GREP {
		ctx.draw_git_grep(x, y)
	}
}

fn (ctx &Vid) draw_ctrlp_files(x, y int) {
	mut j := 0
	for _file in ctx.all_git_files {
		if j == 10 {
			break
		}
		mut file := _file.to_lower()
		file = file.trim_space()
		if !file.contains(ctx.query.to_lower()) {
			continue
		}
		ctx.ft.draw_text(x + 10, y + 60 + 30 * j, file, txt_cfg)
		j++
	}
}

fn (ctx &Vid) draw_top_tasks(x, y int) {
	mut j := 0
	q := ctx.query.to_lower()
	for _task in ctx.top_tasks {
		if j == 10 {
			break
		}
		task := _task.to_lower()
		if !task.contains(q) {
			continue
		}
		// println('DOES CONTAIN "$file" $j')
		ctx.ft.draw_text(x + 10, y + 60 + 30 * j, task, txt_cfg)
		j++
	}
}

fn (ctx &Vid) draw_git_grep(x, y int) {
	for i, line in ctx.gg_lines {
		if i == MaxGrepLines {
			break
		}
		pos := line.index(':')
		path := line.left(pos)
		pos2 := line.index_after(':', pos + 1)
		text := line.right(pos2 + 1).trim_space().left(70)
		yy := y + 60 + 30 * i
		if i == ctx.gg_pos {
			ctx.vg.draw_rect(x, yy, QueryWidth * 2, 30, ctx.cfg.vcolor)
		}
		ctx.ft.draw_text(x + 10, yy, path, txt_cfg)
		ctx.ft.draw_text(x + 210, yy, text, txt_cfg)
	}
}

// Open file on enter
// fn input_enter(s string, ctx * Vid) {
// if s != '' {
fn (ctx mut Vid) ctrlp_open() {
	// Open the first file in the list
	for _file in ctx.all_git_files {
		mut file := _file.to_lower()
		file = file.trim_space()
		if file.contains(ctx.query.to_lower()) {
			mut path := _file.trim_space()
			mut space := ctx.workspace
			if space == '' {
				space = '.'
			}
			path = '$space/$path'
			ctx.view.open_file(path)
			break
		}
	}
}

fn (ctx mut Vid) git_grep() {
	ctx.gg_pos = -1
	s := os.exec('git -C "$ctx.workspace" grep -n "$ctx.search_query"') or { return }
	ctx.gg_lines = s.split_into_lines()
}

fn (ctx &Vid) search(goback bool) {
	if ctx.search_query == '' {
		return
	}
	mut view := ctx.view
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
		line := view.lines[i]
		pos := line.index(ctx.search_query)
		// Already here, skip
		if pos == view.x && i == view.y {
			continue
		}
		if pos > -1 {
			// Found in current screen, dont move it
			if i >= view.from && i <= view.from + ctx.page_height {
				view.y = i
			}
			else {
				ctx.move_to_line(i)
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

