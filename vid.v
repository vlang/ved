// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main

import gl
import gg
import freetype
import glfw
import os
import time
import uiold
import strings
//import darwin

const (
	session_path = os.home_dir() + '.vid/session'
	timer_path   = os.home_dir() + '.vid/timer'
	tasks_path   = os.home_dir() + '.vid/tasks'
)

// TODO enum
enum EditorMode {
	normal = 0
	insert = 1
	query  = 2
	visual = 3
	timer  = 4
}

// Query type
enum QueryType {
	ctrlp  = 0
	search = 1
	cam    = 2
	open   = 3
	ctrlj  = 4
	task   = 5
	grep   = 6
	open_workspace = 7
}

// For syntax highlighting
enum ChunkKind {
	a_string  = 1
	a_comment = 2
	a_key     = 3
}
struct Chunk {
	start int
	end   int
	typ   ChunkKind
}

struct Vid {
mut:
	win_width        int
	win_height       int
	nr_splits        int
	splits_per_workspace int
	page_height      int
	views            []View
	cur_split        int
	view             &View
	mode             EditorMode
	just_switched    bool // for keydown/char events to avoid dup keys
	prev_key         int
	prev_cmd         string
	prev_insert      string
	all_git_files    []string
	top_tasks        []string
	vg               &gg.GG
	ft               &freetype.FreeType
	query            string
	search_query     string
	query_type       QueryType
	main_wnd         &glfw.Window
	workspace        string
	workspace_idx    int
	workspaces       []string
	ylines           []string
	git_diff_plus    string // short git diff stat top right
	git_diff_minus   string
	keys             []string
	chunks           []Chunk
	is_building      bool
	timer            Timer
	task_start_unix  u64
	cur_task         string
	words            []string
	file_y_pos       map[string]int
	refresh          bool
	line_height      int
	char_width       int
	font_size        int
	is_ml_comment    bool
	gg_lines         []string
	gg_pos           int
	cfg              Config
}

struct ViSize {
	width  int
	height int
}

const (
	help_text = '
Usage: vid [options] [files]

Options:
  -h, --help              Display this information.
  -window <window-name>   Launch in a window.
  -dark                   Launch in dark mode.
  -two_splits
'
)

fn main() {
	if '-h' in os.args || '--help' in os.args {
		println(help_text)
		return
	}
	if !os.is_dir(os.home_dir() + '.vid') {
		os.mkdir(os.home_dir() + '.vid') or { panic(err) }
	}
	glfw.init_glfw()
	mut nr_splits := 3
	is_window := '-window' in os.args
	if '-two_splits' in os.args {
		nr_splits = 2
	}
	if is_window {
		nr_splits = 1
	}
	size := if is_window {
		glfw.Size{900, 800}
	}
	else {
		glfw.get_monitor_size()
	}
	if size.width < 1500 {
		nr_splits = 2
	}
	mut vid := &Vid {
		win_width: size.width
		win_height: size.height
		nr_splits: nr_splits
		splits_per_workspace: nr_splits
		cur_split: 0
		mode: 0
		file_y_pos: map[string]int
		line_height: 20
		char_width: 8
		font_size: 13
		view: 0
		vg: 0
		main_wnd: 0
		ft: 0
	}
	vid.handle_segfault()
	vid.cfg.init_colors()
	vid.page_height = size.height / vid.line_height - 1
	// TODO V keys only
	keys := 'case defer none match pub struct interface in sizeof assert enum import go ' +
			'return module fn if for break continue asm unsafe mut ' +
			'type const else true else for false use $' + 'if $' + 'else'
	vid.keys = keys.split(' ')
	mut w := glfw.create_window(glfw.WinCfg {
		width: size.width
		height: size.height
		borderless: !is_window
		title: 'Vid'
		ptr: vid
	})
	vid.main_wnd = w
	w.make_context_current()
	gl.init_glad()
	cfg := gg.Cfg {
		width: size.width
		height: size.height
		font_size: vid.font_size
		use_ortho: true
		retina: true
		scale: 2
		window_user_ptr: 0
	}
	vid.vg = gg.new_context(cfg)
	vid.ft = freetype.new_context(cfg)
	vid.timer = new_timer(vid.vg, vid.ft)
	vid.load_all_tasks()
	w.set_user_ptr(vid)
    //
	// TODO linux and windows
	//C.AXUIElementCreateApplication(234)
	uiold.reg_key_vid()
    //
	w.onkeydown(key_down)
	w.onchar(on_char)
	// Open workspaces or a file
	println(os.args)
	mut cur_dir := os.getwd()
	if cur_dir.ends_with('/vid.app/Contents/Resources') {
		cur_dir = cur_dir.replace('/vid.app/Contents/Resources', '')
	}
	// Open a single text file
	if os.args.len == 2 && !os.args[1].starts_with('-') {
		path := os.args[1]
		if !os.exists(path) {
			println('file "$path" does not exist')
			exit(1)
		}
		println('PATH="$path" cur_dir="$cur_dir"')
		if !os.is_dir(path) && !path.starts_with('-') {
			mut workspace := os.dir(path)
			vid.add_workspace(workspace)
			vid.open_workspace(0)
			vid.view.open_file(path)
		}
	}
	// Open multiple workspaces
	else {
		for i, arg in os.args {
			if i == 0 {
				continue
			}
			if arg.starts_with('-') {
				continue
			}
			// relative path
			if !arg.starts_with('/') {
				vid.add_workspace(cur_dir + '/' + arg)
			} else {
				// absolute path
				vid.add_workspace(arg)
			}
		}
		if vid.workspaces.len == 0 {
			vid.add_workspace(cur_dir)
		}
		vid.open_workspace(0)
	}
	vid.load_session()
	vid.load_timer()
	//println(int(glfw.get_time() -t))
	go vid.loop()
	gl.clear()
	gl.clear_color(vid.cfg.bgcolor.r, vid.cfg.bgcolor.g, vid.cfg.bgcolor.b, 255)
	vid.refresh = true
	for !vid.main_wnd.should_close() {
		if vid.refresh || vid.mode == .timer {
			gl.clear()
			gl.clear_color(vid.cfg.bgcolor.r, vid.cfg.bgcolor.g, vid.cfg.bgcolor.b, 255)
		}
		vid.draw()
		if vid.mode == .timer {
			vid.timer.draw()
		}
		w.swap_buffers()
		glfw.wait_events()
	}
}

fn (vid &Vid) split_width() int {
	mut split_width := vid.win_width / vid.nr_splits + 60
	if split_width < 300 {
		split_width = vid.win_width
	}
	return split_width
}

fn (mut vid Vid) draw() {
	view := vid.view
	split_width := vid.split_width()
	// Splits from and to
	from := vid.workspace_idx * vid.splits_per_workspace
	to := from + vid.splits_per_workspace
	// Not a full refresh? Means we need to refresh only current split.
	if !vid.refresh {
		split_x := split_width * (vid.cur_split - from)
		vid.vg.draw_rect(f32(split_x), 0, f32(split_width - 1), f32(vid.win_height), vid.cfg.bgcolor)
	}
	now := time.now()
	// Coords
	y := (vid.view.y - vid.view.from) * vid.line_height + vid.line_height
	// Cur line
	line_x := split_width * (vid.cur_split - from) + vid.view.padding_left + 10
	vid.vg.draw_rect(f32(line_x), f32(y - 1), f32(split_width - vid.view.padding_left - 10), f32(vid.line_height), vid.cfg.vcolor)
	// V selection
	mut v_from := vid.view.vstart + 1
	mut v_to := vid.view.vend + 1
	if view.vend < view.vstart {
		// Swap start and end if we go beyond the start
		v_from = vid.view.vend + 1
		v_to = vid.view.vstart + 1
	}
	for yy := v_from; yy <= v_to; yy++ {
		vid.vg.draw_rect(f32(line_x), f32((yy - vid.view.from) * vid.line_height),
			f32(split_width - vid.view.padding_left), f32(vid.line_height), vid.cfg.vcolor)
	}
	// Tab offset for cursor
	line := vid.view.line()
	mut cursor_tab_off := 0
	for i := 0; i < line.len && i < vid.view.x; i++ {
		// if rune != '\t' {
		if int(line[i]) != vid.cfg.tab {
			break
		}
		cursor_tab_off++
	}
	// Black title background
	vid.vg.draw_rect(0, 0, f32(vid.win_width), f32(vid.line_height), vid.cfg.title_color)
	// Current split has dark blue title
	// vid.vg.draw_rect(split_x, 0, split_width, vid.line_height, gx.rgb(47, 11, 105))
	// Title (file paths)
	for i := to - 1; i >= from; i-- {
		v := vid.views[i]
		mut name := v.short_path
		if v.changed && !v.path.ends_with('/out') {
			name = '$name [+]'
		}
		vid.ft.draw_text(vid.split_x(i - from) + v.padding_left + 10, 1, name, vid.cfg.file_name_cfg)
	}
	// Git diff stats
	if vid.git_diff_plus != '+' {
		vid.ft.draw_text(vid.win_width - 400, 1, vid.git_diff_plus, vid.cfg.plus_cfg)
	}
	if vid.git_diff_minus != '-' {
		vid.ft.draw_text(vid.win_width - 350, 1, vid.git_diff_minus, vid.cfg.minus_cfg)
	}
	// Workspaces
	nr_spaces := vid.workspaces.len
	cur_space := vid.workspace_idx + 1
	space_name := short_space(vid.workspace)
	vid.ft.draw_text(vid.win_width - 220, 1, '[$space_name]', vid.cfg.file_name_cfg)
	vid.ft.draw_text(vid.win_width - 150, 1, '$cur_space/$nr_spaces', vid.cfg.file_name_cfg)
	// Time
	vid.ft.draw_text(vid.win_width - 50, 1, now.hhmm(), vid.cfg.file_name_cfg)
	// vid.vg.draw_text(vid.win_width - 550, 1, now.hhmmss(), file_name_cfg)
	// vim top right next to current time
	/*
	if vid.start_unix > 0 {
		minutes := '1m' //vid.timer.minutes()
		vid.ft.draw_text(vid.win_width - 300, 1, '${minutes}m' !,
			vid.cfg.file_name_cfg)
	}
	*/
	if vid.cur_task != '' {
		// Draw current task
		task_text_width := vid.cur_task.len * vid.char_width
		task_x := vid.win_width - split_width - task_text_width - 10
		// vid.timer.vg.draw_text(task_x, 1, vid.timer.cur_task.to_upper(), file_name_cfg)
		vid.ft.draw_text(task_x, 1, vid.cur_task, vid.cfg.file_name_cfg)
		// Draw current task time
		task_time_x := (vid.nr_splits - 1) * split_width - 50
		vid.ft.draw_text(task_time_x, 1, '${vid.task_minutes()}m',
			vid.cfg.file_name_cfg)
	}
	// Splits
	// println('\nsplit from=$from to=$to nrviews=$vid.views.len refresh=$vid.refresh')
	for i := to - 1; i >= from; i-- {
		// J or K is pressed (full refresh disabled for performance), only redraw current split
		if !vid.refresh && i != vid.cur_split {
			continue
		}
		// t := glfw.get_time()
		vid.draw_split(i, from)
		// println('draw split $i: ${ glfw.get_time() - t }')
	}
	// Cursor
	cursor_x := line_x + (vid.view.x + cursor_tab_off * vid.cfg.tab_size) * vid.char_width
	vid.vg.draw_empty_rect(f32(cursor_x), f32(y - 1), f32(vid.char_width), f32(vid.line_height), vid.cfg.cursor_color)
	// query window
	if vid.mode == .query {
		vid.draw_query()
	}
}

fn (vid &Vid) split_x(i int) int {
	return vid.split_width() * (i)
}

fn (mut vid Vid) draw_split(i, split_from int) {
	view := vid.views[i]
	vid.is_ml_comment = false
	split_width := vid.split_width()
	split_x := split_width * (i - split_from)
	// Vertical split line
	vid.vg.draw_line(f32(split_x), f32(vid.line_height + 1), f32(split_x), f32(vid.win_height), vid.cfg.split_color)
	// Lines
	mut line_nr := 1// relative y
	for j := view.from; j < view.from + vid.page_height && j < view.lines.len; j++ {
		line := view.lines[j]
		if line.len > 5000 {
			panic('line len too big! views[$i].lines[$j] ($line.len) path=$vid.view.path')
		}
		x := split_x + view.padding_left
		y := line_nr * vid.line_height
		// Error bg
		if view.error_y == j {
			vid.vg.draw_rect(f32(x + 10), f32(y - 1), f32(split_width - view.padding_left - 10), f32(vid.line_height), vid.cfg.errorbgcolor)
		}
		// Line number
		line_number := j + 1
		vid.ft.draw_text(x+3, y, '$line_number', vid.cfg.line_nr_cfg)
		// Tab offset
		mut line_x := x + 10
		mut nr_tabs := 0
		// for k := 0; k < line.len; k++ {
		for c in line {
			if c != `\t` {
				// if int(line[j]) != TAB {
				break
			}
			nr_tabs++
			line_x += vid.char_width * vid.cfg.tab_size
		}
		// Number of chars to display in this view
		if line.len > 0 {
			// mut max := (split_width - view.padding_left - vid.char_width * TAB_SIZE *
			// nr_tabs) / vid.char_width - 1
			max := vid.max_chars(nr_tabs)
			if view.y == j {
				// Display entire line if its current
				// if line.len > max {
				// vid.vg.draw_rect(line_x, y - 1, vid.win_width, line_height, vcolor)
				// }
				// max = line.len
			}
			s := line.limit(max)
			if view.hl_on {
				vid.draw_line(line_x, y, s)// SYNTAX HL
			}
			else {
				vid.ft.draw_text(line_x, y, line, vid.cfg.txt_cfg)// NO SYNTAX
			}
		}
		line_nr++
	}
}

fn (vid &Vid) max_chars(nr_tabs int) int {
	width := vid.split_width() -vid.view.padding_left - vid.char_width * vid.cfg.tab_size * nr_tabs
	return width / vid.char_width - 1
}

fn (mut vid Vid) add_chunk(typ ChunkKind, start, end int) {
	chunk := Chunk {
		typ: typ
		start: start
		end: end
	}
	vid.chunks << chunk
}

fn (mut vid Vid) draw_line(x, y int, line string) {
	// Red/green test hack
	if line.contains('[32m') &&
	line.contains('PASS') {
		vid.ft.draw_text(x, y, line[5..], vid.cfg.green_cfg)
		return
	}
	else if line.contains('[31m') &&
	line.contains('FAIL') {
		vid.ft.draw_text(x, y, line[5..], vid.cfg.red_cfg)
		return
	//} else if line[0] == `-` {
	}
	vid.chunks = []
	//vid.chunks.len = 0 // TODO V should not allow this
	for i := 0; i < line.len; i++ {
		start := i
		// Comment // #
		if i > 0 && line[i - 1] == `/` && line[i] == `/` {
			vid.add_chunk(.a_comment, start - 1, line.len)
			break
		}
		if line[i] == `#` {
			vid.add_chunk(.a_comment, start, line.len)
			break
		}
		// Comment   /*
		if i > 0 && line[i - 1] == `/` && line[i] == `*` {
			// All after /* is  a comment
			vid.add_chunk(.a_comment, start, line.len)
			vid.is_ml_comment = true
			break
		}
		// End of /**/
		if i > 0 && line[i - 1] == `*` && line[i] == `/` {
			// All before */ is still a comment
			vid.add_chunk(.a_comment, 0, start + 1)
			vid.is_ml_comment = false
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
			vid.add_chunk(.a_string, start, i + 1)
		}
		if line[i] == `"` {
			i++
			for i < line.len - 1 && line[i] != `"` {
				i++
			}
			if i >= line.len {
				i = line.len - 1
			}
			vid.add_chunk(.a_string, start, i + 1)
		}
		// Key
		for i < line.len && is_alpha_underscore(int(line[i])) {
			i++
		}
		word := line[start..i]
		// println('word="$word"')
		if word in vid.keys {
			// println('$word is key')
			vid.add_chunk(.a_key, start, i)
			// println('adding key. len=$vid.chunks.len')
		}
	}
	if vid.is_ml_comment {
		vid.ft.draw_text(x, y, line, vid.cfg.comment_cfg)
		return
	}
	if vid.chunks.len == 0 {
		// println('no chunks')
		vid.ft.draw_text(x, y, line, vid.cfg.txt_cfg)
		return
	}
	mut pos := 0
	// println('"$line" nr chunks=$vid.chunks.len')
	// TODO use runes
	// runes := msg.runes.slice_fast(chunk.pos, chunk.end)
	// txt := join_strings(runes)
	for i, chunk in vid.chunks {
		// println('chunk #$i start=$chunk.start end=$chunk.end typ=$chunk.typ')
		// Initial text chunk (not initial, but the one right before current chunk,
		// since we don't have a seperate chunk for text)
		if chunk.start > pos + 1 {
			s := line[pos..chunk.start]
			vid.ft.draw_text(x + pos * vid.char_width, y, s, vid.cfg.txt_cfg)
		}
		// Keyword string etc
		typ := chunk.typ
		cfg := match typ {
			.a_key { vid.cfg.key_cfg }
			.a_string { vid.cfg.string_cfg }
			.a_comment { vid.cfg.comment_cfg }
		}
		s := line[chunk.start..chunk.end]
		vid.ft.draw_text(x + chunk.start * vid.char_width, y, s, cfg)
		pos = chunk.end
		// Final text chunk
		if i == vid.chunks.len - 1 && chunk.end < line.len {
			final := line[chunk.end..line.len]
			vid.ft.draw_text(x + pos * vid.char_width, y, final, vid.cfg.txt_cfg)
		}
	}
}

// mouse click
//fn on_click(cwnd *C.GLFWwindow, button, action, mods int) {
	// wnd := glfw.Window {
	// data: cwnd
	// }
	// pos := wnd.get_cursor_pos()
	// println('CLICK $pos.x $pos.y')
	// mut ctx := &Vid(wnd.get_user_ptr())
	//  printf("mouse click %p\n", glfw__Window_get_user_ptr(&wnd));
	// Mouse coords to x,y
	// vid.view.y = pos.y / line_height - 1
	// vid.view.x = (pos.x - vid.view.padding_left) / char_width - 1
//}

// fn key_down(wnd * ui.Window, c char, mods int, code int) {
fn key_down(wnd &glfw.Window, key int, code int, action, mods int) {
	if action != 2 && action != 1 {
		return
	}
	//  printf("glfw vi.v key down key=%d key_char=%c code=%d action=%d mods=%d\n",
	//  key,key, code, action, mods);
	// single super
	if key == glfw.key_left_super {
		return
	}
	mut vid := &Vid(glfw.get_window_user_pointer(wnd))
	mode := vid.mode
	super := mods == 8 || mods == 2
	shift := mods == 1
	if key == glfw.key_escape {
		vid.mode = .normal
	}
	// Reset error line
	mut view := vid.view
	view.error_y = -1
	match mode {
		.normal { 		vid.key_normal(key, super, shift) }
		.visual { 		vid.key_visual(key, super, shift) }
		.insert { 		vid.key_insert(key, super) }
		.query { 		vid.key_query(key, super) }
		.timer { 		vid.timer.key_down(key, super) }
	}
}

fn on_char(wnd &glfw.Window, code u32, mods int) {
	mut vid := &Vid(glfw.get_window_user_pointer(wnd))
	mode := vid.mode
	if vid.just_switched {
		vid.just_switched = false
		return
	}
	buf := [0, 0, 0, 0, 0] !
	s := utf32_to_str_no_malloc(code,  buf.data)
	//s := utf32_to_str(code)
	//println('s="$s" s0="$s0"')
	match mode {
	.insert { vid.char_insert(s) }
	.query {
		vid.gg_pos = -1
		vid.char_query(s)
	}
	.normal {
		// on char on normal only for replace with r
		if !vid.just_switched && vid.prev_key == C.GLFW_KEY_R {
			if s != 'r' {
				vid.view.r(s)
				vid.prev_key = 0
				vid.prev_cmd = 'r'
				vid.prev_insert = s
			}
			return
		}
	}
	else {}
	}
}

fn (mut vid Vid) key_query(key int, super bool) {
	match key {
	C.GLFW_KEY_BACKSPACE {
		vid.gg_pos = -1
		if vid.query_type != .search && vid.query_type != .grep {
			if vid.query.len == 0 {
				return
			}
			vid.query = vid.query[..vid.query.len - 1]
		}
		else {
			if vid.search_query.len == 0 {
				return
			}
			vid.search_query = vid.search_query[..vid.search_query.len - 1]
		}
		return
	}
	C.GLFW_KEY_ENTER {
		if vid.query_type == .ctrlp {
			vid.ctrlp_open()
		}
		else if vid.query_type == .cam {
			vid.git_commit()
		}
		else if vid.query_type == .open {
			vid.view.open_file(vid.query)
		}
		else if vid.query_type == .task {
			vid.insert_task()
			vid.cur_task = vid.query
			vid.task_start_unix = time.now().unix
			vid.save_timer()
		}
		else if vid.query_type == .grep {
			// Key down was pressed after typing, now pressing enter opens the file
			if vid.gg_pos > -1 && vid.gg_lines.len > 0 {
				line := vid.gg_lines[vid.gg_pos]
				path := line.all_before(':')
				line_nr := line[path.len+1..].int() -1
				vid.view.open_file(vid.workspace + '/' + path)
				vid.view.move_to_line(line_nr)
				vid.view.zz()
				vid.mode = .normal
			}
			else {
				// Otherwise just do a git grep on a submitted query
				vid.git_grep()
			}
			return
		}
		else {
			vid.search(false)
		}
		vid.mode = .normal
		return
	}
	C.GLFW_KEY_ESCAPE {
		vid.mode = .normal
		return
	}
	C.GLFW_KEY_DOWN {
		if vid.mode == .query && vid.query_type == .grep {
			vid.gg_pos++
		}
	}
	C.GLFW_KEY_TAB {// TODO COPY PASTA
		if vid.mode == .query && vid.query_type == .grep {
			vid.gg_pos++
		}
	}
	C.GLFW_KEY_UP {
		println('.a_key UP')
		if vid.mode == .query && vid.query_type == .grep {
			vid.gg_pos--
			if vid.gg_pos < 0 {
				vid.gg_pos = 0
			}
		}
	}
	C.GLFW_KEY_V {
		if super {
			clip := vid.main_wnd.get_clipboard_text()
			vid.query = vid.query + clip
		}
	}
	else {}
	}
}

fn (vid &Vid) is_in_blog() bool {
	return vid.view.path.contains('/blog/') && vid.view.path.contains('2020')
}

fn (vid &Vid) git_commit() {
	text := vid.query
	dir := vid.workspace
	os.system('git -C $dir commit -am "$text"')
	//os.system('gitter $dir')
}

fn (mut vid Vid) key_insert(key int, super bool) {
	match key {
	C.GLFW_KEY_BACKSPACE {
		vid.view.backspace(vid.cfg.backspace_go_up)
	}
	C.GLFW_KEY_ENTER {
		vid.view.enter()
	}
	C.GLFW_KEY_ESCAPE {
		vid.mode = .normal
	}
	C.GLFW_KEY_TAB {
		vid.view.insert_text('\t')
	}
	C.GLFW_KEY_LEFT {
		if vid.view.x > 0 {
			vid.view.x--
		}
	}
	C.GLFW_KEY_RIGHT {
		vid.view.l()
	}
	C.GLFW_KEY_UP {
		vid.view.k()
		//vid.refresh = false
	}
	C.GLFW_KEY_DOWN {
		vid.view.j()
		//vid.refresh = false
	}
	else {}
	}
	if (key == C.GLFW_KEY_L || key == C.GLFW_KEY_S) && super {
		vid.view.save_file()
		vid.mode = .normal
		return
	}
	if super && key == C.GLFW_KEY_U {
		vid.mode = .normal
		vid.key_u()
		return
	}
	// Insert macro   TODO  customize
	if super && key == C.GLFW_KEY_G {
		vid.view.insert_text('<code></code>')
		vid.view.x -= 7
	}
	// Autocomplete
	if key == C.GLFW_KEY_N && super {
		vid.ctrl_n()
		return
	}
	if key == C.GLFW_KEY_V && super {
		// vid.view.insert_text(ui.get_clipboard_text())
		clip := vid.main_wnd.get_clipboard_text()
		vid.view.insert_text(clip)
		return
	}
}

fn (mut vid Vid) ctrl_n() {
	line := vid.view.line()
	mut i := vid.view.x - 1
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
	for map_word in vid.words {
		// If any word starts with our subword, add the rest
		if map_word.starts_with(word) {
			vid.view.insert_text(map_word[word.len..])
			return
		}
	}
}

fn (mut vid Vid) key_normal(key int, super, shift bool) {
	mut view := vid.view
	vid.refresh = true
	if vid.prev_key == C.GLFW_KEY_R {
		return
	}
	match key {
		// Full screen => window
	C.GLFW_KEY_ENTER {
		if false && super {
			vid.nr_splits = 1
			vid.win_width = 600
			vid.win_height = 500
			glfw.post_empty_event()
		}
	}
	C.GLFW_KEY_PERIOD {
		if shift {
			// >
			vid.view.shift_right()
		}
		else {
			vid.dot()
		}
	}
	C.GLFW_KEY_COMMA {
		if shift {
			// <
			vid.view.shift_left()
		}
	}
	C.GLFW_KEY_SLASH {
		if shift {
			vid.search_query = ''
			vid.mode = .query
			vid.just_switched = true
			vid.query_type = .grep
		}
		else {
			vid.search_query = ''
			vid.mode = .query
			vid.just_switched = true
			vid.query_type = .search
		}
	}
	C.GLFW_KEY_F5 {
		vid.run_file()
		// vid.char_width -= 1
		// vid.line_height -= 1
		// vid.font_size -= 1
		// vid.page_height = WIN_HEIGHT / vid.line_height - 1
		// case C.GLFW_KEY_F6:
		// vid.char_width += 1
		// vid.line_height += 1
		// vid.font_size += 1
		// vid.page_height = WIN_HEIGHT / vid.line_height - 1
		// vid.vg = gg.new_context(WIN_WIDTH, WIN_HEIGHT, vid.font_size)
	}
	C.GLFW_KEY_MINUS {
		if super {
			vid.get_git_diff_full()
		}
	}
	C.GLFW_KEY_EQUAL {
		vid.open_blog()
	}
	C.GLFW_KEY_0 {
		if super {
			vid.query = ''
			vid.mode = .query
			vid.query_type = .task
		}
	}
	C.GLFW_KEY_A {
		if shift {
			vid.view.shift_a()
			vid.prev_cmd = 'A'
			vid.set_insert()
		}
	}
	C.GLFW_KEY_C {
		if super {
			vid.query = ''
			vid.mode = .query
			vid.query_type = .cam
		}
		if shift {
			vid.prev_insert = vid.view.shift_c()
			vid.set_insert()
		}
	}
	C.GLFW_KEY_D {
		if super {
			vid.prev_split()
			return
		}
		if vid.prev_key == C.GLFW_KEY_D {
			vid.view.dd()
			return
		}
		else if vid.prev_key == C.GLFW_KEY_G {
			vid.go_to_def()
		}
	}
	C.GLFW_KEY_E {
		if super {
			vid.next_split()
			return
		}
		if vid.prev_key == C.GLFW_KEY_C {
			view.ce()
		}
		else if vid.prev_key == C.GLFW_KEY_D {
			view.de()
		}
	}
	C.GLFW_KEY_I {
		if shift {
			vid.view.shift_i()
			vid.set_insert()
			vid.prev_cmd = 'I'
		}
		else {
			vid.set_insert()
		}
	}
	C.GLFW_KEY_J {
		if shift {
			vid.view.join()
		}
		else if super {
			// vid.mode = .query
			// vid.query_type = CTRLJ
		}
		else {
			// println('J isb=$vid.is_building')
			vid.view.j()
			// if !vid.is_building {
			//vid.refresh = false
			// }
		}
	}
	C.GLFW_KEY_K {
		vid.view.k()
		// if !vid.is_building {
		//vid.refresh = false
		// }
	}
	C.GLFW_KEY_N {
		if shift {
			// backwards search
			vid.search(true)
		}
		else {
			vid.search(false)
		}
	}
	C.GLFW_KEY_O {
		if shift && super {
			vid.mode = .query
			vid.query_type = .open_workspace
			vid.query = ''
		}
		else if super {
			vid.mode = .query
			vid.query_type = .open
			vid.query = ''
			return
		}
		else if shift {
			vid.view.shift_o()
			vid.set_insert()
		}
		else {
			vid.view.o()
			vid.set_insert()
		}
	}
	C.GLFW_KEY_P {
		if super {
			vid.mode = .query
			vid.query_type = .ctrlp
			vid.load_git_tree()
			return
		}
		else {
			view.p()
		}
	}
	C.GLFW_KEY_R {
		if super {
			view.reopen()
		}
		else {
			vid.prev_key = C.GLFW_KEY_R
		}
	}
	C.GLFW_KEY_T {
		if super {
			//vid.timer.get_data(false)
			vid.timer.load_tasks()
			vid.mode = .timer
		}
		else {
			// if vid.prev_key == C.GLFW_KEY_T {
			view.tt()
		}
	}
	C.GLFW_KEY_H {
		if shift {
			vid.view.shift_h()
		}
		else if vid.view.x > 0 {
			vid.view.x--
		}
	}
	C.GLFW_KEY_L {
		if super {
			vid.view.save_file()
		}
		else if shift {
			vid.view.move_to_page_bot()
		}
		else {
			vid.view.l()
		}
	}
	C.GLFW_KEY_F6 {
		if super {
		}
	}
	C.GLFW_KEY_G {
		// go to end
		if shift && !super {
			vid.view.shift_g()
		}
		// copy file path to clipboard
		else if super {
			vid.main_wnd.set_clipboard_text(vid.view.path)
		}
		// go to beginning
		else {
			if vid.prev_key == C.GLFW_KEY_G {
				vid.view.gg()
			}
		}
	}
	C.GLFW_KEY_F {
		if super {
			vid.view.shift_f()
		}
	}
	C.GLFW_KEY_B {
		if super {
			// force crash
			// # void*a = 0; int b = *(int*)a;
			vid.view.shift_b()
		}
		else {
			vid.view.b()
		}
	}
	C.GLFW_KEY_U {
		if super {
			vid.key_u()
		}
	}
	C.GLFW_KEY_V {
		vid.mode = .visual
		view.vstart = view.y
		view.vend = view.y
	}
	C.GLFW_KEY_W {
		if vid.prev_key == C.GLFW_KEY_C {
			view.cw()
		}
		else if vid.prev_key == C.GLFW_KEY_D {
			view.dw()
		}
		else {
			view.w()
		}
	}
	C.GLFW_KEY_X {
		vid.view.delete_char()
	}
	C.GLFW_KEY_Y {
		if vid.prev_key == C.GLFW_KEY_Y {
			vid.view.yy()
		}
		if super {
			go vid.build_app2()
		}
	}
	C.GLFW_KEY_Z {
		if vid.prev_key == C.GLFW_KEY_Z {
			vid.view.zz()
		}
		// Next workspace
	}
	C.GLFW_KEY_RIGHT_BRACKET {
		if super {
			vid.open_workspace(vid.workspace_idx + 1)
		}
	}
	C.GLFW_KEY_LEFT_BRACKET {
		if super {
			vid.open_workspace(vid.workspace_idx - 1)
		}
	}
	C.GLFW_KEY_8 {
		if shift {
			vid.star()
		}
	}
	C.GLFW_KEY_LEFT {
		if vid.view.x > 0 {
			vid.view.x--
		}
	}
	C.GLFW_KEY_RIGHT {
		vid.view.l()
	}
	C.GLFW_KEY_UP {
		vid.view.k()
		//vid.refresh = false
	}
	C.GLFW_KEY_DOWN {
		vid.view.j()
		//vid.refresh = false
	}
	else {}

	}
	if key != C.GLFW_KEY_R {
		// otherwise R is triggered when we press C-R
		vid.prev_key = key
	}
}

// Find current word under cursor
fn (vid &Vid) word_under_cursor() string {
	line := vid.view.line()
	// First go left
	mut start := vid.view.x
	for start > 0 && is_alpha_underscore(int(line[start])) {
		start--
	}
	// Now go right
	mut end := vid.view.x
	for end < line.len && is_alpha_underscore(int(line[end])) {
		end++
	}
	mut word := line[start + 1..end]
	word = word.trim_space()
	return word
}

fn (mut vid Vid) star() {
	vid.search_query = vid.word_under_cursor()
	vid.search(false)
}

fn (mut vid Vid) char_insert(s string) {
	if int(s[0]) < 32 {
		return
	}
	vid.view.insert_text(s)
	vid.prev_insert = vid.prev_insert + s
}

fn (mut vid Vid) char_query(s string) {
	if int(s[0]) < 32 {
		return
	}
	mut q := vid.query
	if vid.query_type == .search || vid.query_type == .grep {
		q = vid.search_query
		vid.search_query = '${q}${s}'
	}
	else {
		vid.query = q + s
	}
}

fn (mut vid Vid) key_visual(key int, super, shift bool) {
	mut view := vid.view
	match key {
	C.GLFW_KEY_ESCAPE {
		vid.exit_visual()
	}
	C.GLFW_KEY_J {
		view.vend++
		if view.vend >= view.lines.len {
			view.vend = view.lines.len - 1
		}
		// Scroll
		if view.vend >= view.from + view.page_height {
			view.from++
		}
	}
	C.GLFW_KEY_K {
		view.vend--
	}
	C.GLFW_KEY_Y {
		view.y_visual()
		vid.mode = .normal
	}
	C.GLFW_KEY_D {
		view.d_visual()
		vid.mode = .normal
	}
	C.GLFW_KEY_Q {
		if vid.prev_key == C.GLFW_KEY_G {
			vid.view.gq()
		}
	}
	C.GLFW_KEY_PERIOD {
		if shift {
			// >
			vid.view.shift_right()
		}
	}
	C.GLFW_KEY_COMMA {
		if shift {
			// >
			vid.view.shift_left()
		}
	}
	else {}
	}
	if key != C.GLFW_KEY_R {
		// otherwise R is triggered when we press C-R
		vid.prev_key = key
	}
}

fn (mut vid Vid) update_view() {
	vid.view = &vid.views[vid.cur_split]
}

fn (mut vid Vid) set_insert() {
	vid.mode = .insert
	vid.prev_insert = ''
	vid.just_switched = true
}

fn (mut vid Vid) exit_visual() {
	vid.mode = .normal
	mut view := vid.view
	view.vstart = -1
	view.vend = -1
}

fn (mut vid Vid) dot() {
	prev_cmd := vid.prev_cmd
	match prev_cmd {
	'dd' {
		vid.view.dd()
	}
	'dw' {
		vid.view.dw()
		}
	'cw' {
		vid.view.dw()
		// println('dot cw prev i=$vid.prev_insert')
		vid.view.insert_text(vid.prev_insert)
		vid.prev_cmd = 'cw'
		}
	'de' {
		vid.view.de()
		}
	'J'{
		vid.view.join()
		}
	'I' {
		vid.view.shift_i()
		vid.view.insert_text(vid.prev_insert)
		}
	'A' {
		vid.view.shift_a()
		vid.view.insert_text(vid.prev_insert)
		}
	 'r' {
		vid.view.r(vid.prev_insert)
		}
	else {}
	}
}

fn (mut vid Vid) next_split() {
	vid.cur_split++
	if vid.cur_split % vid.splits_per_workspace == 0 {
		vid.cur_split -= vid.splits_per_workspace
	}
	vid.update_view()
}

fn (mut vid Vid) prev_split() {
	if vid.cur_split % vid.splits_per_workspace == 0 {
		vid.cur_split += vid.splits_per_workspace - 1
	}
	else {
		vid.cur_split--
	}
	vid.update_view()
}

fn (mut vid Vid) open_workspace(idx int) {
	if idx >= vid.workspaces.len {
		vid.open_workspace(0)
		return
	}
	if idx < 0 {
		vid.open_workspace(vid.workspaces.len - 1)
		return
	}
	diff := idx - vid.workspace_idx
	vid.workspace_idx = idx
	vid.workspace = vid.workspaces[idx]
	// Update cur split index. If we are in space 0 split 1 and go to
	// space 1, split is updated to 4 (1 + 3 * (1-0))
	vid.cur_split += diff * vid.splits_per_workspace
	vid.update_view()
	// vid.get_git_diff()
}

fn (mut vid Vid) add_workspace(path string) {
	println('add_workspace("$path")')
	// if ! os.exists(path) {
	// ui.alert('"$path" doesnt exist')
	// }
	mut workspace := if path == '.' {
		os.getwd()
	} else {
		path
	}
	if workspace.ends_with('/.') {
		workspace = workspace[..workspace.len-2]
	}
	vid.workspaces << workspace
	for i := 0; i < vid.nr_splits; i++ {
		vid.views << vid.new_view()
	}
}

fn short_space(workspace string) string {
	pos := workspace.last_index('/') or {
		return workspace
	}
	return workspace[pos+1..]
}

fn (mut vid Vid) move_to_line(n int) {
	vid.view.from = n
	vid.view.y = n
}

fn (vid &Vid) save_session() {
	println('saving session...')
	mut f := os.create(session_path) or { panic('fail') }
	for view in vid.views {
		// if view.path == '' {
		// continue
		// }
		if view.path == 'out' {
			continue
		}
		f.writeln(view.path)
	}
	f.close()
}

// TODO fix vals[0].int()
fn toi(s string) u64 {
	return s.u64()
}

fn (vid &Vid) save_timer() {
	mut f := os.create(timer_path) or { return }
	f.writeln('task=$vid.cur_task')
	f.writeln('task_start=$vid.task_start_unix')
	//f.writeln('timer_typ=$vid.timer.cur_type')
	/*
	if vid.timer.started {
		f.writeln('timer_start=$vid.timer.start_unix')
	}
	else {
		f.writeln('timer_start=0')
	}
	*/
	f.close()
}

fn (mut vid Vid) load_timer() {
	// task=do work
	// task_start=1223212221
	// timer_typ=7
	// timer_start=12321321
	lines := os.read_lines(timer_path) or { return }
	if lines.len == 0 { return }
	println(lines)
	mut vals := []string{}
	for line in lines {
		words := line.split('=')
		if words.len != 2 {
			vals << ''
			// exit('bad timer format')
		}
		else {
			vals << words[1]
		}
	}
	// mut task := lines[0]
	//println('vals=')
	//println(vals)
	vid.cur_task = vals[0]
	vid.task_start_unix = toi(vals[1])
	//vid.timer.cur_type = toi(vals[2])
	//vid.timer.start_unix = toi(vals[3])
	//vid.timer.started = vid.timer.start_unix != 0
}

fn (mut vid Vid) load_session() {
	println('load session "$session_path"')
	paths := os.read_lines(session_path) or { return }
	println(paths)
	vid.load_views(paths)
}

fn (mut vid Vid) load_views(paths[]string) {
	for i := 0; i < paths.len && i < vid.views.len; i++ {
		// println('loading path')
		// println(paths[i])
		//mut view := &vid.views[i]
		path := paths[i]
		if path == '' || path.contains('=') {
			continue
		}
		//view.open_file(path)
		vid.views[i].open_file(path)
	}
}

fn (vid &Vid) get_git_diff() {
	return
	/*
	dir := vid.workspace
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
	vid.git_diff_plus = '$plus+'
	if vals.len < 3 {
		return
	}
	mut minus := vals[2]
	minus = minus.find_between(' ', 'deletion')
	minus = minus.trim_space()
	vid.git_diff_minus = '$minus-'
*/
}

fn (vid &Vid) get_git_diff_full() string {
	dir := vid.workspace
	os.system('git -C $dir diff > $dir/out')
	mut last_view := vid.get_last_view()
	last_view.open_file('$dir/out')
	// nothing commited (diff = 0), shot git log)
	if last_view.lines.len < 2 {
		// os.system('echo "no diff\n" > $dir/out')
		os.system(
		'git -C $dir log -n 20 --pretty=format:"%ad %s" ' +
		'--simplify-merges --date=format:"%Y-%m-%d %H:%M:%S    "> $dir/out')
		last_view.open_file('$dir/out')
	}
	last_view.gg()
	return 's'
}

fn (vid &Vid) open_blog() {
	now := time.now()
	path := os.home_dir() + 'code/blog/$now.year/${now.month:02d}/${now.day:02d}'
	if !os.exists(path) {
		os.system('touch $path')
	}
	mut last_view := vid.get_last_view()
	last_view.open_file(path)
	last_view.shift_g()
}

fn (vid &Vid) get_last_view() &View {
	pos := (vid.workspace_idx + 1) * vid.splits_per_workspace - 1
	return &vid.views[pos]
}

fn (mut vid Vid) build_app1() {
	vid.build_app('')
	//vid.next_split()

	//glfw.post_empty_event()

	//vid.prev_split()
	//glfw.post_empty_event()
	//vid.refresh = false
}

fn (mut vid Vid) build_app2() {
	vid.build_app('2')
}

fn (mut vid Vid) save_changed_files() {
	for i, view in vid.views {
		if view.changed {
			vid.views[i].save_file()
		}
	}
}

fn (mut vid Vid) build_app(extra string) {
	vid.is_building = true
	println('building...')
	// Save each open file before building
	vid.save_changed_files()
	os.chdir(vid.workspace)
	dir := vid.workspace
	mut last_view := vid.get_last_view()
	//mut f := os.create('$dir/out') or {
		//panic('ff')
		//return
	//}
	os.write_file('$dir/out', 'Building...')
	last_view.open_file('$dir/out')
	out := os.exec('sh $dir/build$extra') or {
		return
	}
	mut f2 := os.create('$dir/out') or {
		panic('fail')
	}
	f2.writeln(out.output)
	f2.close()
	last_view.open_file('$dir/out')
	last_view.shift_g()
	// error line
	alines := out.output.split_into_lines()
	lines := alines.filter(it.contains('.v:'))
	mut no_errors :=  true //!out.output.contains('error:')
	for line in lines {
		// no "warning:" in a line means it's an error
		if !line.contains('warning:') {
			no_errors = false
		}
	}
	for line in lines {
		is_warning := line.contains('warning:')
		// Go to the next warning only if there are no errors.
		// This makes Vid go to errors before warnings.
		if !is_warning || (is_warning && no_errors) {
			vid.go_to_error(line)
			break
		}
	}
	// vid.refresh = true
	glfw.post_empty_event()
	time.sleep(4)// delay is_building to prevent flickering in the right split
	vid.is_building = false
	/*
	// Reopen files (they were formatted)
	for _view in vid.views {
		// ui.alert('reopening path')
		mut view := _view
		println(view.path)
		view.open_file(view.path)
	}
	*/
}

// Run file in current view (go run [file], v run [file], python [file] etc)
// Saves time for user since they don't have to define 'build' for every file
fn (mut vid Vid) run_file() {
	mut view := vid.view
	vid.is_building = true
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
	f.writeln(out.output)
	f.close()
	// TODO COPYPASTA
	mut last_view := vid.get_last_view()
	last_view.open_file('$dir/out')
	last_view.shift_g()
	vid.is_building = false
	// error line
	lines := out.output.split_into_lines()
	for line in lines {
		if line.contains('.v:') {
			vid.go_to_error(line)
			break
		}
	}
	vid.refresh = true
	glfw.post_empty_event()
}

fn (mut vid Vid) go_to_error(line string) {
	// panic: volt/twitch.v:88
	println('go to ERROR $line')
	//if !line.contains('panic:') {
		//return
	//}
	//line = line.replace('panic: ', '')
	pos := line.index('.v:') or {
		println('no 2 :')
		return
	}
	path := line[..pos]
	filename := path.all_after('/') + '.v'
	line_nr := line[pos+3..].all_before(':')
	println('path=$path filename=$filename linenr=$line_nr')
	for i := 0; i < vid.views.len; i++ {
		mut view := &vid.views[i]
		if !view.path.contains(filename) {
			continue
		}
		view.error_y = line_nr.int() -1
		println('error_y=$view.error_y')
		view.move_to_line(view.error_y)
		// view.vid.main_wnd.refresh()
		glfw.post_empty_event()
		return // Done after the first view with the error
	}
	// File with the error is not open right now, do it
	s := os.exec('git -C $vid.workspace ls-files') or { return }
	mut lines := s.output.split_into_lines()
	lines.sort_by_len()
	for git_file in lines {
		if git_file.contains(filename) {
			vid.view.open_file(git_file) //vid.workspace + '/' + line)
			vid.view.error_y = line_nr.int() -1
			vid.view.move_to_line(vid.view.error_y)
			glfw.post_empty_event()
			return
		}
	}
}

fn (mut vid Vid) loop() {
	for {
		vid.refresh = true
		glfw.post_empty_event()
		//vid.timer.tick(vid)
		time.sleep(5)
	}
}

fn (mut vid Vid) key_u() {
	// Run a single test file
	if vid.view.path.ends_with('_test.v') {
		vid.run_file()
	}
	else {
		vid.refresh = true
		go vid.build_app1()
		glfw.post_empty_event()
	}
}

fn (mut vid Vid) go_to_def() {
	word := vid.word_under_cursor()
	query := ') $word'
	mut view := vid.view
	for i, line in view.lines {
		if line.contains(query) {
			vid.move_to_line(i)
			return
		}
	}
	// Not found in current file, try all files in the git tree
	for _file in vid.all_git_files {
		mut file := _file.to_lower()
		file = file.trim_space()
		if !file.ends_with('.v') {
			continue
		}
		file = '$vid.workspace/$file'
		lines := os.read_lines(file) or { continue }
		// println('trying file $file with $lines.len lines')
		for j, line in lines {
			if line.contains(query) {
				view.open_file(file)
				vid.move_to_line(j)
				break
			}
		}
	}
}

fn segfault_sigaction(signal int, si voidptr, arg voidptr) {
	println('crash!')
	/*
	mut vid := &Vid{!}
	//# vid=g_vid;
	# vid=arg;
	println(vid.line_height)
	// vid.save_session()
	// vid.save_timer()
	vid.save_changed_files()
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

fn (vid &Vid) handle_segfault() {
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

fn (vid &Vid) task_minutes() int {
	now := time.now()
	mut seconds := now.unix - vid.task_start_unix
	if vid.task_start_unix == 0 {
		seconds = 0
	}
	return int(seconds / 60)
}

const (
	max_task_len = 40
)

fn (vid &Vid) insert_task() {
	if vid.cur_task == '' || vid.task_minutes() == 0 {
		return
	}
	mut f := os.open_append(tasks_path) or { panic(err) }
	task_name := vid.cur_task.limit(max_task_len) + strings.repeat(` `,
		max_task_len - vid.cur_task.len)
	mins := vid.task_minutes().str() + 'm'
	mins_pad := strings.repeat(` `,		4 - mins.len)
	f.writeln('| $task_name | $mins $mins_pad | ' +
		time.unix(int(vid.task_start_unix)).format() + ' | ' +
		time.now().hhmm() + ' |')
	f.writeln('|-----------------------------------------------------------------------------|')
	f.close()
}
