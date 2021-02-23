// Copyright (c) 2019-2021 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import gg
import os
import time
import uiold
import strings
// import sokol.sapp
import clipboard

// import darwin

const (
	settings_path     = os.join_path(os.home_dir(), '.ved')
	codeblog_path     = os.join_path(os.home_dir(), 'code', 'blog')
	session_path      = os.join_path(settings_path, 'session')
	timer_path        = os.join_path(settings_path, 'timer')
	tasks_path        = os.join_path(settings_path, 'tasks')
	max_nr_workspaces = 10
)

struct Ved {
mut:
	win_width            int
	win_height           int
	nr_splits            int
	splits_per_workspace int
	page_height          int
	views                []View
	cur_split            int
	view                 &View
	mode                 EditorMode
	just_switched        bool // for keydown/char events to avoid dup keys
	prev_key             gg.KeyCode
	prev_cmd             string
	prev_insert          string // for `.` (re-enter the text that was just entered via cw etc)
	all_git_files        []string
	top_tasks            []string
	gg                   &gg.Context
	query                string
	search_query         string
	query_type           QueryType
	workspace            string
	workspace_idx        int
	workspaces           []string
	ylines               []string
	git_diff_plus        string // short git diff stat top right
	git_diff_minus       string
	keys                 []string
	chunks               []Chunk
	is_building          bool
	timer                Timer
	task_start_unix      u64
	cur_task             string
	words                []string
	file_y_pos           map[string]int // to save current line for each file s
	refresh              bool = true
	line_height          int
	char_width           int
	// font_size        int
	is_ml_comment bool
	gg_lines      []string
	gg_pos        int
	cfg           Config
	cb            &clipboard.Clipboard
	open_paths    [][]string // all open files (tabs) per workspace: open_paths[workspace_idx] == ['a.txt', b.v']
	prev_y        int        // for jumping back ('')
	now           time.Time  // cached value of time.now() to avoid calling it for every frame
}

// For syntax highlighting
enum ChunkKind {
	a_string = 1
	a_comment = 2
	a_key = 3
}

enum EditorMode {
	normal = 0
	insert = 1
	query = 2
	visual = 3
	timer = 4
}

enum QueryType {
	ctrlp = 0
	search = 1
	cam = 2
	open = 3
	ctrlj = 4
	task = 5
	grep = 6
	open_workspace = 7
}

struct Chunk {
	start int
	end   int
	typ   ChunkKind
}

struct ViSize {
	width  int
	height int
}

const (
	help_text = '
Usage: ved [options] [files]

Options:
  -h, --help              Display this information.
  -window <window-name>   Launch in a window.
  -dark                   Launch in dark mode.
  -two_splits
'
)

const (
	fpath = os.resource_abs_path('RobotoMono-Regular.ttf')
)

fn main() {
	args := os.args.clone()
	if '-h' in args || '--help' in args {
		println(help_text)
		return
	}
	if !os.is_dir(settings_path) {
		os.mkdir(settings_path) or { panic(err) }
	}
	mut nr_splits := 3
	is_window := '-window' in args
	if '-two_splits' in args {
		nr_splits = 2
	}
	if is_window {
		nr_splits = 1
	}
	// size := gg.Size{5120, 2880}
	mut size := gg.screen_size()
	if size.width == 0 || size.height == 0 {
		size = gg.Size{2560, 1480}
		if '-laptop' in args {
			size = gg.Size{1440 * 1, 900 * 1}
			nr_splits = 2
		}
	}
	// TODO
	/*
	size := if is_window {
		gg.Size{900, 800}
	}
	else {
		gg.Size{900, 800}

		//glfw.get_monitor_size()
	}
	*/
	if size.width < 1500 {
		nr_splits = 2
	}
	mut ved := &Ved{
		win_width: size.width
		win_height: size.height
		nr_splits: nr_splits
		splits_per_workspace: nr_splits
		cur_split: 0
		mode: EditorMode(0)
		line_height: 20
		char_width: 8 // font_size: 13
		view: 0
		gg: 0
		cb: clipboard.new()
		open_paths: [][]string{len: max_nr_workspaces}
	}
	ved.handle_segfault()
	ved.cfg.init_colors()
	println('height=$size.height')
	ved.page_height = size.height / ved.line_height - 1
	// TODO V keys only
	keys := 'case defer none match pub struct interface in sizeof assert enum import go ' +
		'return module fn if for break continue asm unsafe mut is ' +
		'type const else true else for false use $' + 'if $' + 'else'
	ved.keys = keys.split(' ')
	ved.gg = gg.new_context(
		width: size.width
		height: size.height // borderless_window: !is_window
		fullscreen: !is_window
		window_title: 'Ved'
		create_window: true
		user_data: ved
		use_ortho: true
		scale: 2
		bg_color: ved.cfg.bgcolor
		frame_fn: frame
		event_fn: on_event
		keydown_fn: key_down
		char_fn: on_char
		font_path: os.resource_abs_path('RobotoMono-Regular.ttf')
		ui_mode: true
	)
	println('FULL SCREEN=${!is_window}')
	ved.timer = new_timer(ved.gg)
	ved.load_all_tasks()
	// TODO linux and windows
	// C.AXUIElementCreateApplication(234)
	uiold.reg_key_vid()
	// Open workspaces or a file
	$if debug {
		println('args:')
		println(args)
	}
	mut cur_dir := os.getwd()
	if cur_dir.ends_with('/ved.app/Contents/Resources') {
		cur_dir = cur_dir.replace('/ved.app/Contents/Resources', '')
	}
	// Open a single text file
	mut first_launch := false
	if args.len > 1 && os.is_file(args[args.len - 1]) {
		path := args[args.len - 1]
		if !os.exists(path) {
			println('file "$path" does not exist')
			exit(1)
		}
		println('PATH="$path" cur_dir="$cur_dir"')
		if !os.is_dir(path) && !path.starts_with('-') {
			mut workspace := os.dir(path)
			ved.add_workspace(workspace)
			ved.open_workspace(0)
			ved.view.open_file(path)
		}
	}
	// Open multiple workspaces
	else {
		println('open multiple workspaces')
		for i, arg in args {
			println(arg)
			if i == 0 {
				continue
			}
			if arg.starts_with('-') {
				continue
			}
			// relative path
			if !arg.starts_with('/') {
				ved.add_workspace(cur_dir + '/' + arg)
			} else {
				// absolute path
				ved.add_workspace(arg)
			}
		}
		if ved.workspaces.len == 0 {
			first_launch = true
			ved.add_workspace(cur_dir)
		}
		ved.open_workspace(0)
	}
	ved.load_session()
	ved.load_timer()
	println('first_launch=$first_launch')
	if ved.workspaces.len == 1 && first_launch && !os.exists(session_path) {
		ved_exe_dir := os.dir(os.executable())
		ved.view.open_file(os.join_path(ved_exe_dir, 'welcome.txt'))
	}
	go ved.loop()
	ved.refresh = true
	ved.gg.run()
}

fn on_event(e &gg.Event, mut ved Ved) {
	ved.refresh = true
}

fn (ved &Ved) split_width() int {
	mut split_width := ved.win_width / ved.nr_splits + 60
	if split_width < 300 {
		split_width = ved.win_width
	}
	return split_width
}

fn frame(mut ved Ved) {
	// if !ved.refresh {
	// return
	// }
	// println('frame() ${time.now()}')
	ved.gg.begin()
	ved.draw()
	if ved.mode == .timer {
		ved.timer.draw()
	}
	ved.gg.end()
	ved.refresh = false
}

fn (mut ved Ved) draw() {
	view := ved.view
	split_width := ved.split_width()
	// Splits from and to
	from := ved.workspace_idx * ved.splits_per_workspace
	to := from + ved.splits_per_workspace
	// Not a full refresh? Means we need to refresh only current split.
	if !ved.refresh {
		// split_x := split_width * (ved.cur_split - from)
		// ved.gg.draw_rect(split_x, 0, split_width - 1, ved.win_height, ved.cfg.bgcolor)
	}
	// Coords
	y := (ved.view.y - ved.view.from) * ved.line_height + ved.line_height
	// Cur line
	line_x := split_width * (ved.cur_split - from) + ved.view.padding_left + 10
	ved.gg.draw_rect(line_x, y - 1, split_width - ved.view.padding_left - 10, ved.line_height,
		ved.cfg.vcolor)
	// V selection
	mut v_from := ved.view.vstart + 1
	mut v_to := ved.view.vend + 1
	if view.vend < view.vstart {
		// Swap start and end if we go beyond the start
		v_from = ved.view.vend + 1
		v_to = ved.view.vstart + 1
	}
	for yy := v_from; yy <= v_to; yy++ {
		ved.gg.draw_rect(line_x, (yy - ved.view.from) * ved.line_height, split_width - ved.view.padding_left,
			ved.line_height, ved.cfg.vcolor)
	}
	// Tab offset for cursor
	line := ved.view.line()
	mut cursor_tab_off := 0
	for i := 0; i < line.len && i < ved.view.x; i++ {
		// if rune != '\t' {
		if int(line[i]) != ved.cfg.tab {
			break
		}
		cursor_tab_off++
	}
	// Black title background
	ved.gg.draw_rect(0, 0, ved.win_width, ved.line_height, ved.cfg.title_color)
	// Current split has dark blue title
	// ved.gg.draw_rect(split_x, 0, split_width, ved.line_height, gx.rgb(47, 11, 105))
	// Title (file paths)
	for i := to - 1; i >= from; i-- {
		v := ved.views[i]
		mut name := v.short_path
		if v.changed && !v.path.ends_with('/out') {
			name = '$name [+]'
		}
		ved.gg.draw_text(ved.split_x(i - from) + v.padding_left + 10, 1, name, ved.cfg.file_name_cfg)
	}
	// Git diff stats
	if ved.git_diff_plus != '+' {
		ved.gg.draw_text(ved.win_width - 400, 1, ved.git_diff_plus, ved.cfg.plus_cfg)
	}
	if ved.git_diff_minus != '-' {
		ved.gg.draw_text(ved.win_width - 350, 1, ved.git_diff_minus, ved.cfg.minus_cfg)
	}
	// Workspaces
	nr_spaces := ved.workspaces.len
	cur_space := ved.workspace_idx + 1
	space_name := short_space(ved.workspace)
	ved.gg.draw_text(ved.win_width - 220, 1, '[$space_name]', ved.cfg.file_name_cfg)
	ved.gg.draw_text(ved.win_width - 150, 1, '$cur_space/$nr_spaces', ved.cfg.file_name_cfg)
	// Time
	ved.gg.draw_text(ved.win_width - 50, 1, ved.now.hhmm(), ved.cfg.file_name_cfg)
	// ved.gg.draw_text(ved.win_width - 550, 1, now.hhmmss(), file_name_cfg)
	// vim top right next to current time
	/*
	if ved.start_unix > 0 {
		minutes := '1m' //ved.timer.minutes()
		ved.gg.draw_text(ved.win_width - 300, 1, '${minutes}m' !,
			ved.cfg.file_name_cfg)
	}
	*/
	if ved.cur_task != '' {
		// Draw current task
		task_text_width := ved.cur_task.len * ved.char_width
		task_x := ved.win_width - split_width - task_text_width - 10
		// ved.timer.gg.draw_text(task_x, 1, ved.timer.cur_task.to_upper(), file_name_cfg)
		ved.gg.draw_text(task_x, 1, ved.cur_task, ved.cfg.file_name_cfg)
		// Draw current task time
		task_time_x := (ved.nr_splits - 1) * split_width - 50
		ved.gg.draw_text(task_time_x, 1, '${ved.task_minutes()}m', ved.cfg.file_name_cfg)
	}
	// Draw "i" in insert mode
	if ved.mode == .insert {
		ved.gg.draw_text(5, 1, '-i-', ved.cfg.file_name_cfg)
	}
	// Splits
	// println('\nsplit from=$from to=$to nrviews=$ved.views.len refresh=$ved.refresh')
	for i := to - 1; i >= from; i-- {
		// J or K is pressed (full refresh disabled for performance), only redraw current split
		if !ved.refresh && i != ved.cur_split {
			// continue
		}
		// t := glfw.get_time()
		ved.draw_split(i, from)
		// println('draw split $i: ${ glfw.get_time() - t }')
	}
	// Cursor
	mut cursor_x := line_x + (ved.view.x + cursor_tab_off * ved.cfg.tab_size) * ved.char_width
	if cursor_tab_off > 0 {
		// If there's a tab, need to shift the cursor to the left by  nr of tabsl
		cursor_x -= ved.char_width * cursor_tab_off
	}
	ved.gg.draw_empty_rect(cursor_x, y - 1, ved.char_width, ved.line_height, ved.cfg.cursor_color)
	// ved.gg.draw_text_def(cursor_x + 500, y - 1, 'tab=$cursor_tab_off x=$cursor_x view_x=$ved.view.x')
	// query window
	if ved.mode == .query {
		ved.draw_query()
	}
}

fn (ved &Ved) split_x(i int) int {
	return ved.split_width() * (i)
}

fn (mut ved Ved) draw_split(i int, split_from int) {
	view := ved.views[i]
	ved.is_ml_comment = false
	split_width := ved.split_width()
	split_x := split_width * (i - split_from)
	// Vertical split line
	ved.gg.draw_line(split_x, ved.line_height + 1, split_x, ved.win_height, ved.cfg.split_color)
	// Lines
	mut line_nr := 1 // relative y
	for j := view.from; j < view.from + ved.page_height && j < view.lines.len; j++ {
		line := view.lines[j]
		if line.len > 5000 {
			println('line len too big! views[$i].lines[$j] ($line.len) path=$ved.view.path')
			continue
		}
		x := split_x + view.padding_left
		y := line_nr * ved.line_height
		// Error bg
		if view.error_y == j {
			ved.gg.draw_rect(x + 10, y - 1, split_width - view.padding_left - 10, ved.line_height,
				ved.cfg.errorbgcolor)
		}
		// Line number
		line_number := j + 1
		ved.gg.draw_text(x + 3, y, '$line_number', ved.cfg.line_nr_cfg)
		// Tab offset
		mut line_x := x + 10
		mut nr_tabs := 0
		// for k := 0; k < line.len; k++ {
		for c in line {
			if c != `\t` {
				break
			}
			nr_tabs++
			line_x += ved.char_width * ved.cfg.tab_size
		}
		mut s := line[nr_tabs..] // tabs have been skipped, remove them from the string
		if s == '' {
			line_nr++
			continue
		}
		// Number of chars to display in this view
		// mut max := (split_width - view.padding_left - ved.char_width * TAB_SIZE *
		// nr_tabs) / ved.char_width - 1
		max := ved.max_chars(nr_tabs)
		if view.y == j {
			// Display entire line if its current
			// if line.len > max {
			// ved.gg.draw_rect(line_x, y - 1, ved.win_width, line_height, vcolor)
			// }
			// max = line.len
		}
		if max > 0 && max < s.len {
			s = s[..max]
		}
		if view.hl_on {
			// println('line="$s" nrtabs=$nr_tabs line_x=$line_x')
			ved.draw_text_line(line_x, y, s)
		} else {
			ved.gg.draw_text(line_x, y, s, ved.cfg.txt_cfg)
		}
		line_nr++
	}
}

fn (ved &Ved) max_chars(nr_tabs int) int {
	width := ved.split_width() - ved.view.padding_left - ved.char_width * ved.cfg.tab_size * nr_tabs
	return width / ved.char_width - 1
}

fn (mut ved Ved) add_chunk(typ ChunkKind, start int, end int) {
	chunk := Chunk{
		typ: typ
		start: start
		end: end
	}
	ved.chunks << chunk
}

fn (mut ved Ved) draw_text_line(x int, y int, line string) {
	// Red/green test hack
	/*
	if line.contains('[32m') && line.contains('PASS') {
		ved.gg.draw_text(x, y, line[5..], ved.cfg.green_cfg)
		return
	} else if line.contains('[31m') && line.contains('FAIL') {
		ved.gg.draw_text(x, y, line[5..], ved.cfg.red_cfg)
		return
	}
	*/
	// } else if line[0] == `-` {
	ved.chunks = []
	// ved.chunks.len = 0 // TODO V should not allow this
	for i := 0; i < line.len; i++ {
		start := i
		// Comment // #
		if i > 0 && line[i - 1] == `/` && line[i] == `/` {
			ved.add_chunk(.a_comment, start - 1, line.len)
			break
		}
		if line[i] == `#` {
			ved.add_chunk(.a_comment, start, line.len)
			break
		}
		// Comment   /*
		if i > 0 && line[i - 1] == `/` && line[i] == `*` {
			// All after /* is  a comment
			ved.add_chunk(.a_comment, start, line.len)
			ved.is_ml_comment = true
			break
		}
		// End of /**/
		if i > 0 && line[i - 1] == `*` && line[i] == `/` {
			// All before */ is still a comment
			ved.add_chunk(.a_comment, 0, start + 1)
			ved.is_ml_comment = false
			break
		}
		// String
		if line[i] == `\'` {
			i++
			for i < line.len - 1 && line[i] != `\'` {
				i++
			}
			if i >= line.len {
				i = line.len - 1
			}
			ved.add_chunk(.a_string, start, i + 1)
		}
		if line[i] == `"` {
			i++
			for i < line.len - 1 && line[i] != `"` {
				i++
			}
			if i >= line.len {
				i = line.len - 1
			}
			ved.add_chunk(.a_string, start, i + 1)
		}
		// Key
		for i < line.len && is_alpha_underscore(int(line[i])) {
			i++
		}
		word := line[start..i]
		// println('word="$word"')
		if word in ved.keys {
			// println('$word is key')
			ved.add_chunk(.a_key, start, i)
			// println('adding key. len=$ved.chunks.len')
		}
	}
	if ved.is_ml_comment {
		ved.gg.draw_text(x, y, line, ved.cfg.comment_cfg)
		return
	}
	if ved.chunks.len == 0 {
		// println('no chunks')
		ved.gg.draw_text(x, y, line, ved.cfg.txt_cfg)
		return
	}
	mut pos := 0
	// println('"$line" nr chunks=$ved.chunks.len')
	// TODO use runes
	// runes := msg.runes.slice_fast(chunk.pos, chunk.end)
	// txt := join_strings(runes)
	for i, chunk in ved.chunks {
		// println('chunk #$i start=$chunk.start end=$chunk.end typ=$chunk.typ')
		// Initial text chunk (not necessarily initial, but the one right before current chunk,
		// since we don't have a seperate chunk for text)
		if chunk.start > pos {
			s := line[pos..chunk.start]
			ved.gg.draw_text(x + pos * ved.char_width, y, s, ved.cfg.txt_cfg)
		}
		// Keyword string etc
		typ := chunk.typ
		cfg := match typ {
			.a_key { ved.cfg.key_cfg }
			.a_string { ved.cfg.string_cfg }
			.a_comment { ved.cfg.comment_cfg }
		}
		s := line[chunk.start..chunk.end]
		ved.gg.draw_text(x + chunk.start * ved.char_width, y, s, cfg)
		pos = chunk.end
		// Final text chunk
		if i == ved.chunks.len - 1 && chunk.end < line.len {
			final := line[chunk.end..line.len]
			ved.gg.draw_text(x + pos * ved.char_width, y, final, ved.cfg.txt_cfg)
		}
	}
}

// mouse click
// fn on_click(cwnd *C.GLFWwindow, button, action, mods int) {
// wnd := glfw.Window {
// data: cwnd
// }
// pos := wnd.get_cursor_pos()
// println('CLICK $pos.x $pos.y')
// mut ctx := &Ved(wnd.get_user_ptr())
// printf("mouse click %p\n", glfw__Window_get_user_ptr(&wnd));
// Mouse coords to x,y
// ved.view.y = pos.y / line_height - 1
// ved.view.x = (pos.x - ved.view.padding_left) / char_width - 1
// }
fn key_down(key gg.KeyCode, mod gg.Modifier, mut ved Ved) {
	super := mod == .super
	shift := mod == .shift
	if key == .escape {
		if ved.mode == .visual {
			ved.exit_visual()
		}
		ved.mode = .normal
	}
	// Reset error line
	ved.view.error_y = -1
	match ved.mode {
		.normal { ved.key_normal(key, mod) }
		.visual { ved.key_visual(key, super, shift) }
		.insert { ved.key_insert(key, mod) }
		.query { ved.key_query(key, super) }
		.timer { ved.timer.key_down(key, super) }
	}
	ved.gg.refresh_ui()
}

fn on_char(code u32, mut ved Ved) {
	if ved.just_switched {
		ved.just_switched = false
		return
	}
	buf := [0, 0, 0, 0, 0]
	s := unsafe { utf32_to_str_no_malloc(code, buf) } // .data)
	// s := utf32_to_str(code)
	// println('s="$s" code="$code"')
	match ved.mode {
		.insert {
			ved.char_insert(s)
		}
		.query {
			ved.gg_pos = -1
			ved.char_query(s)
		}
		.normal {
			// on char on normal only for replace with r
			if !ved.just_switched && ved.prev_key == .r {
				if s != 'r' {
					ved.view.r(s)
					ved.prev_key = gg.KeyCode(0)
					ved.prev_cmd = 'r'
					ved.prev_insert = s
				}
				return
			}
		}
		else {}
	}
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
			if ved.query_type == .ctrlp {
				ved.ctrlp_open()
			} else if ved.query_type == .ctrlj {
				ved.ctrlj_open()
			} else if ved.query_type == .cam {
				ved.git_commit()
			} else if ved.query_type == .open {
				ved.view.open_file(ved.query)
			} else if ved.query_type == .task {
				ved.insert_task()
				ved.cur_task = ved.query
				ved.task_start_unix = time.now().unix
				ved.save_timer()
			} else if ved.query_type == .grep {
				// Key down was pressed after typing, now pressing enter opens the file
				if ved.gg_pos > -1 && ved.gg_lines.len > 0 {
					line := ved.gg_lines[ved.gg_pos]
					path := line.all_before(':')
					pos := line.index(':') or { 0 }
					pos2 := line.index_after(':', pos + 1)
					// line_nr := line[path.len + 1..].int() - 1
					line_nr := line[pos + 1..pos2].int() - 1
					ved.view.open_file(ved.workspace + '/' + path)
					ved.view.move_to_line(line_nr)
					ved.view.zz()
					ved.mode = .normal
				} else {
					// Otherwise just do a git grep on a submitted query
					ved.git_grep()
				}
				return
			} else {
				ved.search(false)
			}
			ved.mode = .normal
			return
		}
		.escape {
			ved.mode = .normal
			return
		}
		.down {
			if ved.mode == .query && ved.query_type == .grep {
				ved.gg_pos++
			}
		}
		.tab {
			// TODO COPY PASTA
			if ved.mode == .query && ved.query_type == .grep {
				ved.gg_pos++
			}
			ved.just_switched = true
		}
		.up {
			if ved.mode == .query && ved.query_type == .grep {
				ved.gg_pos--
				if ved.gg_pos < 0 {
					ved.gg_pos = 0
				}
			}
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

fn (ved &Ved) is_in_blog() bool {
	return ved.view.path.contains('/blog/') && ved.view.path.contains('2020')
}

fn (ved &Ved) git_commit() {
	text := ved.query
	dir := ved.workspace
	os.system('git -C $dir commit -am "$text"')
	// os.system('gitter $dir')
}

fn (mut ved Ved) key_insert(key gg.KeyCode, mod gg.Modifier) {
	super := mod == .super || mod == .ctrl
	// shift := mod == .shift
	match key {
		.backspace {
			ved.just_switched = true // prevent backspace symbol being added in char handler
			ved.view.backspace(ved.cfg.backspace_go_up)
		}
		.enter {
			ved.view.enter()
		}
		.escape {
			ved.mode = .normal
		}
		.tab {
			ved.view.insert_text('\t')
		}
		.left {
			if ved.view.x > 0 {
				ved.view.x--
			}
		}
		.right {
			ved.view.l()
		}
		.up {
			ved.view.k()
			// ved.refresh = false
		}
		.down {
			ved.view.j()
			// ved.refresh = false
		}
		else {}
	}
	if (key == .l || key == .s) && super {
		ved.view.save_file()
		ved.mode = .normal
		return
	}
	if super && key == .u {
		ved.mode = .normal
		ved.key_u()
		return
	}
	// Insert macro   TODO  customize
	if super && key == .g {
		ved.view.insert_text('<code></code>')
		ved.view.x -= 7
	}
	// Autocomplete
	if key == .n && super {
		ved.ctrl_n()
		return
	}
	if key == .v && super {
		ved.view.insert_text(ved.cb.paste())
		ved.just_switched = true
	}
}

fn (mut ved Ved) ctrl_n() {
	line := ved.view.line()
	mut i := ved.view.x - 1
	end := i
	for i > 0 && is_alpha_underscore(int(line[i])) {
		i--
	}
	if !is_alpha_underscore(int(line[i])) {
		i++
	}
	mut word := line[i..end + 1]
	word = word.trim_space()
	// Dont autocomplete if  fewer than 3 chars
	if word.len < 3 {
		return
	}
	for map_word in ved.words {
		// If any word starts with our subword, add the rest
		if map_word.starts_with(word) {
			ved.view.insert_text(map_word[word.len..])
			ved.just_switched = true
			return
		}
	}
}

fn (mut ved Ved) key_normal(key gg.KeyCode, mod gg.Modifier) {
	super := mod == .super || mod == .ctrl
	shift := mod == .shift
	// println(int(mod))
	shift_and_super := int(mod) == 9
	mut view := ved.view
	ved.refresh = true
	if ved.prev_key == .r {
		return
	}
	if ved.prev_cmd == 'ci' {
		view.ci(key)
		return
	}
	match key {
		.enter {
			// Full screen => window
			if false && super {
				ved.nr_splits = 1
				ved.win_width = 600
				ved.win_height = 500
				// glfw.post_empty_event()
			}
		}
		.period {
			if shift {
				// >
				ved.view.shift_right()
			} else {
				ved.dot()
			}
		}
		.comma {
			if shift {
				// <
				ved.view.shift_left()
			}
		}
		.slash {
			if shift {
				ved.search_query = ''
				ved.mode = .query
				ved.just_switched = true
				ved.query_type = .grep
			} else {
				ved.search_query = ''
				ved.mode = .query
				ved.just_switched = true
				ved.query_type = .search
			}
		}
		.f5 {
			ved.run_file()
			// ved.char_width -= 1
			// ved.line_height -= 1
			// ved.font_size -= 1
			// ved.page_height = WIN_HEIGHT / ved.line_height - 1
			// case C.GLFW_KEY_F6:
			// ved.char_width += 1
			// ved.line_height += 1
			// ved.font_size += 1
			// ved.page_height = WIN_HEIGHT / ved.line_height - 1
			// ved.vg = gg.new_context(WIN_WIDTH, WIN_HEIGHT, ved.font_size)
		}
		.minus {
			if super {
				ved.get_git_diff_full()
			}
		}
		.equal {
			ved.open_blog()
		}
		.apostrophe {
			if ved.prev_key == .apostrophe {
				ved.prev_key = gg.KeyCode(0)
				ved.move_to_line(ved.prev_y)
				return
			}
		}
		._0 {
			if super {
				ved.query = ''
				ved.mode = .query
				ved.query_type = .task
				ved.just_switched = true
			}
		}
		.a {
			if shift {
				ved.view.shift_a()
				ved.prev_cmd = 'A'
				ved.set_insert()
			}
		}
		.c {
			if super {
				ved.query = ''
				ved.mode = .query
				ved.query_type = .cam
				ved.just_switched = true
			}
			if shift {
				ved.prev_insert = ved.view.shift_c()
				ved.set_insert()
			}
		}
		.d {
			if super {
				ved.prev_split()
				return
			}
			if ved.prev_key == .d {
				ved.view.dd()
				return
			} else if ved.prev_key == .g {
				ved.go_to_def()
			}
		}
		.e {
			if super {
				ved.next_split()
				return
			}
			if ved.prev_key == .c {
				view.ce()
			} else if ved.prev_key == .d {
				view.de()
			}
		}
		.i {
			if shift {
				ved.view.shift_i()
				ved.set_insert()
				ved.prev_cmd = 'I'
			} else {
				if ved.prev_key == .c {
					ved.prev_cmd = 'ci'
				} else {
					ved.set_insert()
				}
			}
		}
		.j {
			if shift {
				ved.view.join()
			} else if super {
				ved.mode = .query
				ved.query_type = .ctrlj
				// ved.load_open_files()
				ved.query = ''
				ved.just_switched = true
			} else {
				// println('J isb=$ved.is_building')
				ved.view.j()
				// if !ved.is_building {
				// ved.refresh = false
				// }
			}
		}
		.k {
			ved.view.k()
			// if !ved.is_building {
			// ved.refresh = false
			// }
		}
		.n {
			if shift {
				// backwards search
				ved.search(true)
			} else {
				ved.search(false)
			}
		}
		.o {
			if shift_and_super {
				ved.mode = .query
				ved.query_type = .open_workspace
				ved.query = ''
			} else if super {
				ved.mode = .query
				ved.query_type = .open
				ved.query = ''
				ved.just_switched = true
				return
			} else if shift {
				ved.view.shift_o()
				ved.set_insert()
			} else {
				ved.view.o()
				ved.set_insert()
			}
		}
		.p {
			if shift_and_super {
				os.system('git -C "$ved.workspace" pull --rebase')
			} else if super {
				ved.mode = .query
				ved.query_type = .ctrlp
				ved.load_git_tree()
				ved.query = ''
				ved.just_switched = true
				return
			} else {
				view.p()
			}
		}
		.r {
			if super {
				view.reopen()
			} else {
				ved.prev_key = .r
			}
		}
		.t {
			if super {
				// ved.timer.get_data(false)
				ved.timer.load_tasks()
				ved.mode = .timer
			} else {
				// if ved.prev_key == C.GLFW_KEY_T {
				view.tt()
			}
		}
		.h {
			if shift {
				ved.view.shift_h()
			} else if ved.view.x > 0 {
				ved.view.x--
			}
		}
		.l {
			if super {
				ved.just_switched = true
				ved.view.save_file()
			} else if shift {
				ved.view.move_to_page_bot()
			} else {
				ved.view.l()
			}
		}
		.f6 {
			if super {
			}
		}
		.g {
			// go to end
			if shift && !super {
				ved.view.shift_g()
				// ved.prev_key = 0
			}
			// copy file path to clipboard
			else if super {
				ved.cb.copy(ved.view.path)
			}
			// go to beginning
			else {
				if ved.prev_key == .g {
					ved.view.gg()
					// ved.prev_key = 0
				} else {
					ved.prev_key = .g
				}
			}
			return
		}
		.f {
			if super {
				ved.view.shift_f()
			}
		}
		.page_down {
			ved.view.shift_f()
		}
		.page_up {
			ved.view.shift_b()
		}
		.b {
			if super {
				// force crash
				// # void*a = 0; int b = *(int*)a;
				ved.view.shift_b()
			} else {
				ved.view.b()
			}
		}
		.u {
			if super {
				ved.key_u()
			}
		}
		.v {
			ved.mode = .visual
			view.vstart = view.y
			view.vend = view.y
		}
		.w {
			if ved.prev_key == .c {
				view.cw()
			} else if ved.prev_key == .d {
				view.dw(true)
			} else {
				view.w()
			}
		}
		.x {
			ved.view.delete_char()
		}
		.y {
			if ved.prev_key == .y {
				ved.view.yy()
			}
			if super {
				go ved.build_app2()
			}
		}
		.z {
			if ved.prev_key == .z {
				ved.view.zz()
			}
			// Next workspace
		}
		.right_bracket {
			if super {
				ved.open_workspace(ved.workspace_idx + 1)
			}
		}
		.left_bracket {
			if super {
				ved.open_workspace(ved.workspace_idx - 1)
			}
		}
		._8 {
			if shift {
				ved.star()
			}
		}
		.left {
			if ved.view.x > 0 {
				ved.view.x--
			}
		}
		.right {
			ved.view.l()
		}
		.up {
			ved.view.k()
			// ved.refresh = false
		}
		.down {
			ved.view.j()
			// ved.refresh = false
		}
		else {}
	}
	if key != .r {
		// otherwise R is triggered when we press C-R
		ved.prev_key = key
	}
}

// Find current word under cursor
fn (ved &Ved) word_under_cursor() string {
	line := ved.view.line()
	// First go left
	mut start := ved.view.x
	for start > 0 && is_alpha_underscore(int(line[start])) {
		start--
	}
	// Now go right
	mut end := ved.view.x
	for end < line.len && is_alpha_underscore(int(line[end])) {
		end++
	}
	mut word := line[start + 1..end]
	word = word.trim_space()
	return word
}

fn (mut ved Ved) star() {
	ved.search_query = ved.word_under_cursor()
	ved.search(false)
}

fn (mut ved Ved) char_insert(s string) {
	if int(s[0]) < 32 {
		return
	}
	ved.view.insert_text(s)
	ved.prev_insert += s
	// println(ved.prev_insert)
}

fn (mut ved Ved) char_query(s string) {
	if int(s[0]) < 32 {
		return
	}
	mut q := ved.query
	if ved.query_type == .search || ved.query_type == .grep {
		q = ved.search_query
		ved.search_query = q + s
	} else {
		ved.query = q + s
	}
}

fn (mut ved Ved) key_visual(key gg.KeyCode, super bool, shift bool) {
	mut view := ved.view
	match key {
		.j {
			view.vend++
			if view.vend >= view.lines.len {
				view.vend = view.lines.len - 1
			}
			// Scroll
			if view.vend >= view.from + view.page_height {
				view.from++
			}
		}
		.k {
			view.vend--
		}
		.y {
			view.y_visual()
			ved.mode = .normal
		}
		.d {
			view.d_visual()
			ved.mode = .normal
		}
		.q {
			if ved.prev_key == .g {
				ved.view.gq()
			}
		}
		.period {
			if shift {
				// >
				ved.view.shift_right()
			}
		}
		.comma {
			if shift {
				// >
				ved.view.shift_left()
			}
		}
		else {}
	}
	if key != .r {
		// otherwise R is triggered when we press C-R
		ved.prev_key = key
	}
}

fn (mut ved Ved) update_view() {
	$if debug {
		println('update view len=$ved.views.len')
	}
	unsafe {
		ved.view = &ved.views[ved.cur_split]
	}
}

fn (mut ved Ved) set_insert() {
	ved.mode = .insert
	ved.prev_insert = ''
	ved.just_switched = true
}

fn (mut ved Ved) exit_visual() {
	println('exit visual')
	ved.mode = .normal
	mut view := ved.view
	view.vstart = -1
	view.vend = -1
}

// repeat previous command
fn (mut ved Ved) dot() {
	prev_cmd := ved.prev_cmd
	match prev_cmd {
		'dd' {
			ved.view.dd()
		}
		'dw' {
			ved.view.dw(true)
		}
		'cw' {
			ved.view.cw()
			println('dot cw prev_insert=$ved.prev_insert')
			ved.view.insert_text(ved.prev_insert)
			ved.prev_cmd = 'cw'
		}
		'de' {
			ved.view.de()
		}
		'J' {
			ved.view.join()
		}
		'I' {
			ved.view.shift_i()
			ved.view.insert_text(ved.prev_insert)
		}
		'A' {
			ved.view.shift_a()
			ved.view.insert_text(ved.prev_insert)
		}
		'r' {
			ved.view.r(ved.prev_insert)
		}
		else {}
	}
}

fn (mut ved Ved) next_split() {
	ved.cur_split++
	if ved.cur_split % ved.splits_per_workspace == 0 {
		ved.cur_split -= ved.splits_per_workspace
	}
	ved.update_view()
}

fn (mut ved Ved) prev_split() {
	if ved.cur_split % ved.splits_per_workspace == 0 {
		ved.cur_split += ved.splits_per_workspace - 1
	} else {
		ved.cur_split--
	}
	ved.update_view()
}

fn (mut ved Ved) open_workspace(idx int) {
	//$if debug {
	println('open workspace($idx)')
	//}
	if idx >= ved.workspaces.len {
		ved.open_workspace(0)
		return
	}
	if idx < 0 {
		ved.open_workspace(ved.workspaces.len - 1)
		return
	}
	diff := idx - ved.workspace_idx
	ved.workspace_idx = idx
	ved.workspace = ved.workspaces[idx]
	// Update cur split index. If we are in space 0 split 1 and go to
	// space 1, split is updated to 4 (1 + 3 * (1-0))
	ved.cur_split += diff * ved.splits_per_workspace
	ved.update_view()
	// ved.get_git_diff()
}

fn (mut ved Ved) add_workspace(path string) {
	//$if debug {
	println('add_workspace("$path")')
	//}
	// if ! os.exists(path) {
	// ui.alert('"$path" doesnt exist')
	// }
	// TODO autofree bug. not freed
	mut workspace := if path == '.' { os.getwd() } else { path }
	if workspace.ends_with('/.') {
		workspace = workspace[..workspace.len - 2]
	}
	if ved.workspaces.len >= max_nr_workspaces {
		// ui.alert('workspace limit')
		return
	}
	ved.workspaces << workspace
	for i := 0; i < ved.nr_splits; i++ {
		ved.views << ved.new_view()
	}
}

fn short_space(workspace string) string {
	pos := workspace.last_index('/') or { return workspace }
	return workspace[pos + 1..]
}

fn (mut ved Ved) move_to_line(n int) {
	ved.prev_y = ved.view.y
	ved.view.from = n
	ved.view.y = n
}

fn (ved &Ved) save_session() {
	println('saving session...')
	mut f := os.create(session_path) or { panic('fail') }
	for i, view in ved.views {
		println('saving view #$i $view.path')
		// if view.path == '' {
		// continue
		// }
		if view.path == 'out' {
			continue
		}
		f.writeln(view.path) or { panic(err) }
	}
	f.close()
}

// TODO fix vals[0].int()
fn toi(s string) u64 {
	return s.u64()
}

fn (ved &Ved) save_timer() {
	mut f := os.create(timer_path) or { return }
	f.writeln('task=$ved.cur_task') or { panic(err) }
	f.writeln('task_start=$ved.task_start_unix') or { panic(err) }
	// f.writeln('timer_typ=$ved.timer.cur_type') or { panic(err) }
	/*
	if ved.timer.started {
		f.writeln('timer_start=$ved.timer.start_unix') or { panic(err) }
	}
	else {
		f.writeln('timer_start=0') or { panic(err) }
	}
	*/
	f.close()
}

fn (mut ved Ved) load_timer() {
	// task=do work
	// task_start=1223212221
	// timer_typ=7
	// timer_start=12321321
	lines := os.read_lines(timer_path) or { return }
	if lines.len == 0 {
		return
	}
	println(lines)
	mut vals := []string{}
	for line in lines {
		words := line.split('=')
		if words.len != 2 {
			vals << ''
			// exit('bad timer format')
		} else {
			vals << words[1]
		}
	}
	// mut task := lines[0]
	// println('vals=')
	// println(vals)
	ved.cur_task = vals[0]
	ved.task_start_unix = toi(vals[1])
	// ved.timer.cur_type = toi(vals[2])
	// ved.timer.start_unix = toi(vals[3])
	// ved.timer.started = ved.timer.start_unix != 0
}

fn (mut ved Ved) load_session() {
	println('load session "$session_path"')
	paths := os.read_lines(session_path) or { return }
	println(paths)
	ved.load_views(paths)
}

fn (mut ved Ved) load_views(paths []string) {
	for i := 0; i < paths.len && i < ved.views.len; i++ {
		// println('loading path')
		// println(paths[i])
		// mut view := &ved.views[i]
		path := paths[i]
		if path == '' || path.contains('=') {
			continue
		}
		// view.open_file(path)
		ved.views[i].open_file(path)
	}
}

fn (ved &Ved) get_git_diff() {
	/*
	return
	dir := ved.workspace
	mut s := os.system('git -C $dir diff --shortstat')
	vals := s.split(',')
	if vals.len < 2 {
		return
	}
	println(vals.len)
	// vals[1] == "2 insertions(+)"
	mut plus := vals[1]
	plus = plus.find_between(' ', 'insertion')
	plus = plus.trim_space()
	ved.git_diff_plus = '$plus+'
	if vals.len < 3 {
		return
	}
	mut minus := vals[2]
	minus = minus.find_between(' ', 'deletion')
	minus = minus.trim_space()
	ved.git_diff_minus = '$minus-'
	*/
}

fn (ved &Ved) get_git_diff_full() string {
	dir := ved.workspace
	os.system('git -C $dir diff > $dir/out')
	mut last_view := ved.get_last_view()
	last_view.open_file('$dir/out')
	// nothing commited (diff = 0), shot git log)
	if last_view.lines.len < 2 {
		// os.system('echo "no diff\n" > $dir/out')
		os.system('git -C $dir log -n 20 --pretty=format:"%ad %s" ' +
			'--simplify-merges --date=format:"%Y-%m-%d %H:%M:%S    "> $dir/out')
		last_view.open_file('$dir/out')
	}
	last_view.gg()
	return 's'
}

fn (ved &Ved) open_blog() {
	now := time.now()
	path := os.join_path(codeblog_path, '$now.year', '${now.month:02d}', '${now.day:02d}')
	if !os.exists(path) {
		os.system('touch $path')
	}
	mut last_view := ved.get_last_view()
	last_view.open_file(path)
	last_view.shift_g()
}

fn (ved &Ved) get_last_view() &View {
	pos := (ved.workspace_idx + 1) * ved.splits_per_workspace - 1
	unsafe {
		return &ved.views[pos]
	}
}

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

fn (mut ved Ved) save_changed_files() {
	for i, view in ved.views {
		if view.changed {
			ved.views[i].save_file()
		}
	}
}

fn (mut ved Ved) build_app(extra string) {
	ved.is_building = true
	println('building...')
	// Save each open file before building
	ved.save_changed_files()
	os.chdir(ved.workspace)
	dir := ved.workspace
	mut last_view := ved.get_last_view()
	// mut f := os.create('$dir/out') or {
	// panic('ff')
	// return
	// }
	os.write_file('$dir/out', 'Building...') or { panic(err) }
	last_view.open_file('$dir/out')
	out := os.exec('sh $dir/build$extra') or { return }
	mut f2 := os.create('$dir/out') or { panic('fail') }
	f2.writeln(out.output) or { panic(err) }
	f2.close()
	last_view.open_file('$dir/out')
	last_view.shift_g()
	// error line
	alines := out.output.split_into_lines()
	lines := alines.filter(it.contains('.v:'))
	mut no_errors := true // !out.output.contains('error:')
	for line in lines {
		// no "warning:" in a line means it's an error
		if !line.contains('warning:') {
			no_errors = false
		}
	}
	for line in lines {
		is_warning := line.contains('warning:')
		// Go to the next warning only if there are no errors.
		// This makes Ved go to errors before warnings.
		if !is_warning || (is_warning && no_errors) {
			ved.go_to_error(line)
			break
		}
	}
	ved.gg.refresh_ui()
	// ved.refresh = true
	// time.sleep(4) // delay is_building to prevent flickering in the right split
	ved.is_building = false
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
	ved.is_building = true
	println('start file run')
	// Save the file before building
	if view.changed {
		view.save_file()
	}
	// go run /a/b/c.go
	// dir is "/a/b/"
	// cd to /a/b/
	// dir := ospath.dir(view.path)
	dir := os.dir(view.path)
	os.chdir(dir)
	out := os.exec('v $view.path') or { return }
	mut f := os.create('$dir/out') or { panic('foo') }
	f.writeln(out.output) or { panic(err) }
	f.close()
	// TODO COPYPASTA
	mut last_view := ved.get_last_view()
	last_view.open_file('$dir/out')
	last_view.shift_g()
	ved.is_building = false
	// error line
	lines := out.output.split_into_lines()
	for line in lines {
		if line.contains('.v:') {
			ved.go_to_error(line)
			break
		}
	}
	ved.refresh = true
}

fn (mut ved Ved) go_to_error(line string) {
	// panic: volt/twitch.v:88
	println('go to ERROR $line')
	// if !line.contains('panic:') {
	// return
	// }
	// line = line.replace('panic: ', '')
	pos := line.index('.v:') or {
		println('no 2 :')
		return
	}
	path := line[..pos]
	filename := path.all_after('/') + '.v'
	vals := line[pos + 3..].split(':')
	println(vals)
	line_nr := vals[0].int()
	col := vals[1].int()
	println('path=$path filename=$filename linenr=$line_nr col=$col')
	for i := 0; i < ved.views.len; i++ {
		mut view := unsafe { &ved.views[i] }
		if !view.path.contains(filename) {
			continue
		}
		view.error_y = line_nr - 1
		println('error_y=$view.error_y')
		view.move_to_line(view.error_y)
		if col > 0 {
			view.x = col - 1
		}
		// view.ved.main_wnd.refresh()
		// Done after the first view with the error
		return
	}
	// File with the error is not open right now, do it
	s := os.exec('git -C $ved.workspace ls-files') or { return }
	mut lines := s.output.split_into_lines()
	lines.sort_by_len()
	for git_file in lines {
		if git_file.contains(filename) {
			ved.view.open_file(git_file) // ved.workspace + '/' + line)
			ved.view.error_y = line_nr - 1
			ved.view.move_to_line(ved.view.error_y)
			return
		}
	}
}

fn (mut ved Ved) loop() {
	for {
		ved.refresh = true
		ved.now = time.now()
		ved.gg.refresh_ui()
		// ved.timer.tick(vid)
		time.wait(5 * time.second)
	}
}

fn (mut ved Ved) key_u() {
	// Run a single test file
	if ved.view.path.ends_with('_test.v') {
		ved.run_file()
	} else {
		ved.refresh = true
		go ved.build_app1()
	}
}

fn (mut ved Ved) go_to_def() {
	word := ved.word_under_cursor()
	query := ') $word'
	mut view := ved.view
	for i, line in view.lines {
		if line.contains(query) {
			ved.move_to_line(i)
			return
		}
	}
	// Not found in current file, try all files in the git tree
	for file_ in ved.all_git_files {
		mut file := file_.to_lower()
		file = file.trim_space()
		if !file.ends_with('.v') {
			continue
		}
		file = '$ved.workspace/$file'
		lines := os.read_lines(file) or { continue }
		// println('trying file $file with $lines.len lines')
		for j, line in lines {
			if line.contains(query) {
				view.open_file(file)
				ved.move_to_line(j)
				break
			}
		}
	}
}

fn segfault_sigaction(signal int, si voidptr, arg voidptr) {
	println('crash!')
	/*
	mut ved := &Ved{!}
	//# vid=g_vid;
	# vid=arg;
	println(ved.line_height)
	// ved.save_session()
	// ved.save_timer()
	ved.save_changed_files()
	// #const char buf[ ] = "your message\n";
	// #write(STDOUT_FILENO, buf, strlen(buf));
	// #printf("Caught segfault at address %p\n", si->si_addr);
	// #send_error(tos("segfault"));
	// #printf("SEGFAULT %08x \n", pthread_self());
	println('forking...')
	// # execv("myvim", (char *[]){ "./myvim", 0});
	println('done forking...')
	*/
	exit(1)
}

fn (ved &Ved) handle_segfault() {
	$if windows {
		return
	}
	/*
	# g_vid= ctx ;
	# struct sigaction sa;
	# int *foo = NULL;
	# memset(&sa, 0, sizeof(struct sigaction));
	# sigemptyset(&sa.sa_mask);
	# sa.sa_sigaction = segfault_sigaction;
	# sa.sa_flags   = SA_SIGINFO;
	# sigaction(SIGSEGV, &sa, 0);
	*/
}

fn (ved &Ved) task_minutes() int {
	mut seconds := ved.now.unix - ved.task_start_unix
	if ved.task_start_unix <= 0 {
		seconds = 0
	}
	return int(seconds / 60)
}

const (
	max_task_len = 40
)

fn (ved &Ved) insert_task() {
	if ved.cur_task == '' || ved.task_minutes() == 0 {
		return
	}
	mut f := os.open_append(tasks_path) or { panic(err) }
	task_name := ved.cur_task.limit(max_task_len) +
		strings.repeat(` `, max_task_len - ved.cur_task.len)
	mins := ved.task_minutes().str() + 'm'
	mins_pad := strings.repeat(` `, 4 - mins.len)
	f.writeln('| $task_name | $mins $mins_pad | ' + time.unix(int(ved.task_start_unix)).format() +
		' | ' + time.now().hhmm() + ' |') or { panic(err) }
	f.writeln('|-----------------------------------------------------------------------------|') or {
		panic(err)
	}
	f.close()
}
