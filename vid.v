// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main

import (
	gl
	gx 
	gg
	freetype 
	glfw
	os
	//ospath
	glm
	time
	rand
	//gx
	//ui
	//darwin
) 

const ( 
	vcolor       = gx.Color{226, 233, 241} // selection color 
	split_color  = gx.Color{223, 223, 223} 
	bgcolor      = gx.Color{245, 245, 245}
	string_color = gx.Color{179, 58, 44}
	key_color    = gx.Color{74, 103, 154}
	title_color  = gx.Color{40, 40, 40}
) 

const ( 
	SESSION_PATH = os.home_dir() + '/.vppsession' // TODO rename consts 
	TIMER_PATH   = os.home_dir() + '/.vpptimer'
	DefaultDir   = os.home_dir() + '/code'
)

// TODO enum 
const (
	NORMAL = 0
	INSERT = 1
	QUERY  = 2
	VISUAL = 3
	TIMER  = 4
)

const (
	file_name_cfg = gx.TextCfg { color: gx.White, size: 18, }
	plus_cfg      = gx.TextCfg { color: gx.Green, size: 18, }
	minus_cfg     = gx.TextCfg { color: gx.Green, size: 18, }
	line_nr_cfg   = gx.TextCfg { color: gx.DarkGray, size: 18, align: gx.ALIGN_RIGHT, }
	key_cfg       = gx.TextCfg { size: 18, color: key_color, }
	string_cfg    = gx.TextCfg { size: 18, color: string_color, }
	comment_cfg   = gx.TextCfg { size: 18, color: gx.DarkGray, }
	green_cfg     = gx.TextCfg { size: 18, color: gx.Green, }
	red_cfg       = gx.TextCfg { size: 18, color: gx.Red}
)

const (
	TAB          = int(`\t`) 
	TAB_SIZE     = 8
)

// Query type
const (
	CTRLP  = 0
	SEARCH = 1
	CAM    = 2
	OPEN   = 3
	CTRLJ  = 4
	TASK   = 5
	GREP   = 6
)

// For syntax highlighting 
const (
	STRING  = 1
	COMMENT = 2
	KEY     = 3
)
struct Chunk {
	start int
	end   int
	typ   int
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
	view             *View
	mode             int
	just_switched    bool // for keydown/char events to avoid dup keys
	prev_key         int
	prev_cmd         string
	prev_insert      string
	all_git_files    []string
	top_tasks        []string
	vg               *gg.GG
	ft               *freetype.Context 
	query            string
	search_query     string
	query_type       int
	main_wnd         *glfw.Window
	workspace        string
	workspace_idx    int
	workspaces       []string
	ylines           []string
	git_diff_plus    string // short git diff stat top right
	git_diff_minus   string
	keys             []string
	chunks           []Chunk
	is_building      bool
	//timer            *Timer
	words            []string
	file_y_pos       map[string]int
	refresh          bool
	line_height      int
	char_width       int
	font_size        int
	is_ml_comment    bool
	gg_lines         []string
	gg_pos           int
}

struct ViSize {
	width  int
	height int
}

fn main() {
	glfw.init()
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
	//t := glfw.get_time()
	mut ctx := &Vid {
		win_width: size.width
		win_height: size.height
		nr_splits: nr_splits
		splits_per_workspace: nr_splits
		cur_split: 0
		mode: 0
		//timer: timer
		file_y_pos: map[string]int{}
		line_height: 20
		char_width: 8
		font_size: 13
		view: 0
		vg: 0
		main_wnd: 0
	}
	ctx.handle_segfault()
	ctx.page_height = size.height / ctx.line_height - 1
	// TODO V keys only 
	keys := 'pub struct interface in default sizeof assert enum import go return module package '+
		 'fn if for break continue range mut type const else switch case true else for false use' 
	ctx.keys = keys.split(' ')
	//println(ctx.keys)
	mut w := glfw.create_window(glfw.WinCfg {
		width: size.width 
		height: size.height 
		borderless: !is_window 
		title: 'Vid' 
		ptr: ctx 
	})
	ctx.main_wnd = w
	w.make_context_current()
	gl.init_glad()
	cfg := gg.Cfg {
		width: size.width
		height: size.height
		font_size: ctx.font_size
		use_ortho: true
		retina: true
		scale: 2
	}
	ctx.vg = gg.new_context(cfg)
	ctx.ft = freetype.new_context(cfg)
	ctx.load_all_tasks()
	w.set_user_ptr(ctx)
	$if mac {
		// TODO global shortcut, defined in ui module
		//C.reg_key_vid()
	}
	w.onkeydown(key_down)
	w.onchar(on_char)
	// Open workspaces 
	cur_dir := os.getwd() 
	for i, arg in os.args {
		if i == 0 {
			continue 
		} 
		if !arg.starts_with('-') { 
			ctx.add_workspace(cur_dir + '/' + arg) 
		}
	}
	if ctx.workspaces.len == 0 { 
		ctx.add_workspace(cur_dir) 
	} 
	ctx.open_workspace(0)
	ctx.load_session()
	ctx.load_timer()
	//println(int(glfw.get_time() -t))
	go ctx.loop()
	gl.clear()
	gl.clear_color(245, 245, 245, 255)
	ctx.refresh = true
	for !ctx.main_wnd.should_close() {
		if ctx.refresh || ctx.mode == TIMER {
			gl.clear()
			gl.clear_color(245, 245, 245, 255)
		}
		ctx.draw()
		//if ctx.mode == TIMER {
			//timer.draw()
		//}
		w.swap_buffers()
		glfw.wait_events()
	}
}

fn (ctx &Vid) split_width() int {
	mut split_width := ctx.win_width / ctx.nr_splits + 60
	if split_width < 300 {
		split_width = ctx.win_width
	}
	return split_width
}

fn (ctx mut Vid) draw() {
	view := ctx.view
	split_width := ctx.split_width()
	// Splits from and to
	from := ctx.workspace_idx * ctx.splits_per_workspace
	to := from + ctx.splits_per_workspace
	// Not a full refresh? Means we need to refresh only current split.
	if !ctx.refresh {
		split_x := split_width * (ctx.cur_split - from)
		ctx.vg.draw_rect(split_x, 0, split_width - 1, ctx.win_height, bgcolor)
	}
	now := time.now()
	// Coords
	y := (ctx.view.y - ctx.view.from) * ctx.line_height + ctx.line_height
	// Cur line
	line_x := split_width * (ctx.cur_split - from) + ctx.view.padding_left + 10
	ctx.vg.draw_rect(line_x, y - 1, split_width - ctx.view.padding_left - 10, ctx.line_height, vcolor)
	// V selection
	mut v_from := ctx.view.vstart + 1
	mut v_to := ctx.view.vend + 1
	if view.vend < view.vstart {
		// Swap start and end if we go beyond the start
		v_from = ctx.view.vend + 1
		v_to = ctx.view.vstart + 1
	}
	for yy := v_from; yy <= v_to; yy++ {
		ctx.vg.draw_rect(line_x, (yy - ctx.view.from) * ctx.line_height,
		split_width - ctx.view.padding_left, ctx.line_height, vcolor)
	}
	// Tab offset for cursor
	line := ctx.view.line()
	mut cursor_tab_off := 0
	for i := 0; i < line.len && i < ctx.view.x; i++ {
		// if rune != '\t' {
		if int(line[i]) != TAB {
			break
		}
		cursor_tab_off++
	}
	// Black title background
	ctx.vg.draw_rect(0, 0, ctx.win_width, ctx.line_height, title_color)
	// Current split has dark blue title
	// ctx.vg.draw_rect(split_x, 0, split_width, ctx.line_height, gx.rgb(47, 11, 105))
	// Title (file paths)
	for i := to - 1; i >= from; i-- {
		v := ctx.views[i]
		mut name := v.short_path
		if v.changed && !v.path.ends_with('/out') {
			name = '$name [+]' !
		}
		ctx.ft.draw_text(ctx.split_x(i - from) + v.padding_left + 10, 1, name, file_name_cfg)
	}
	// Git diff stats
	if ctx.git_diff_plus != '+' {
		ctx.ft.draw_text(ctx.win_width - 400, 1, ctx.git_diff_plus, plus_cfg)
	}
	if ctx.git_diff_minus != '-' {
		ctx.ft.draw_text(ctx.win_width - 350, 1, ctx.git_diff_minus, minus_cfg)
	}
	// Workspaces
	nr_spaces := ctx.workspaces.len
	cur_space := ctx.workspace_idx + 1
	space_name := short_space(ctx.workspace)
	ctx.ft.draw_text(ctx.win_width - 220, 1, '[$space_name]' !, file_name_cfg)
	ctx.ft.draw_text(ctx.win_width - 150, 1, '$cur_space/$nr_spaces' !, file_name_cfg)
	// Time
	ctx.ft.draw_text(ctx.win_width - 50, 1, now.hhmm(), file_name_cfg)
	// ctx.vg.draw_text(ctx.win_width - 550, 1, now.hhmmss(), file_name_cfg)
	// vim top right next to current time
/* 
	if ctx.timer.start_unix > 0 {
		minutes := ctx.timer.minutes()
		ctx.timer.vg.draw_text(ctx.win_width - 300, 1, '${minutes}m' !, file_name_cfg)
	}
	if ctx.timer.cur_task != '' {
		// Draw current task
		task_text_width := ctx.timer.cur_task.len * ctx.char_width
		task_x := ctx.win_width - split_width - task_text_width - 10
		// ctx.timer.vg.draw_text(task_x, 1, ctx.timer.cur_task.to_upper(), file_name_cfg)
		ctx.timer.vg.draw_text(task_x, 1, ctx.timer.cur_task, file_name_cfg)
		// Draw current task time
		task_time_x := (ctx.nr_splits - 1) * split_width - 50
		ctx.timer.vg.draw_text(task_time_x, 1, '${ctx.timer.task_minutes()}m' !, file_name_cfg)
	}
*/ 
	// Splits
	// println('\nsplit from=$from to=$to nrviews=$ctx.views.len refresh=$ctx.refresh')
	for i := to - 1; i >= from; i-- {
		// J or K is pressed (full refresh disabled for performance), only redraw current split
		if !ctx.refresh && i != ctx.cur_split {
			continue
		}
		// t := glfw.get_time()
		ctx.draw_split(i, from)
		// println('draw split $i: ${ glfw.get_time() - t }')
	}
	// Cursor
	cursor_x := line_x + (ctx.view.x + cursor_tab_off * TAB_SIZE) * ctx.char_width
	ctx.vg.draw_empty_rect(cursor_x, y - 1, ctx.char_width, ctx.line_height, gx.Black)
	// query window
	if ctx.mode == QUERY {
		ctx.draw_query()
	}
}

fn (ctx &Vid) split_x(i int) int {
	return ctx.split_width() * (i)
}

fn (ctx mut Vid) draw_split(i, split_from int) {
	view := ctx.views[i]
	ctx.is_ml_comment = false
	split_width := ctx.split_width()
	split_x := split_width * (i - split_from)
	// Vertical split line
	ctx.vg.draw_line_c(split_x, ctx.line_height + 1, split_x, ctx.win_height, split_color) 
	// Lines
	mut line_nr := 1// relative y
	for j := view.from; j < view.from + ctx.page_height && j < view.lines.len; j++ {
		line := view.lines[j]
		if line.len > 5000 {
			panic('line len too big! views[$i].lines[$j] ($line.len) path=$ctx.view.path')
		}
		x := split_x + view.padding_left
		y := line_nr * ctx.line_height
		// Error bg
		if view.error_y == j {
			ctx.vg.draw_rect(x + 10, y - 1, split_width - view.padding_left - 10, ctx.line_height, gx.rgb(240, 0, 0))
		}
		// Line number
		line_number := j + 1
		ctx.ft.draw_text(x+3, y, '$line_number'!, line_nr_cfg)
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
			line_x += ctx.char_width * TAB_SIZE
		}
		// Number of chars to display in this view
		if line.len > 0 {
			// mut max := (split_width - view.padding_left - ctx.char_width * TAB_SIZE *
			// nr_tabs) / ctx.char_width - 1
			max := ctx.max_chars(nr_tabs)
			if view.y == j {
				// Display entire line if its current
				// if line.len > max {
				// ctx.vg.draw_rect(line_x, y - 1, ctx.win_width, line_height, vcolor)
				// }
				// max = line.len
			}
			s := line.left(max)
			if view.hl_on {
				ctx.draw_line(line_x, y, s)// SYNTAX HL
			}
			else {
				ctx.ft.draw_text(line_x, y, line, txt_cfg)// NO SYNTAX
			}
		}
		line_nr++
	}
}

fn (ctx &Vid) max_chars(nr_tabs int) int {
	width := ctx.split_width() -ctx.view.padding_left - ctx.char_width * TAB_SIZE * nr_tabs
	return width / ctx.char_width - 1
}

fn (ctx mut Vid) add_chunk(typ, start, end int) {
	chunk := Chunk {
		typ: typ
		start: start
		end: end
	}
	ctx.chunks << chunk
}

fn (ctx mut Vid) draw_line(x, y int, line string) {
	txt_cfg := gx.TextCfg {
		size: 18,
		color: gx.Black,
	}
	// Red/green test hack
	if line.contains('[32m') &&
	line.contains('PASS') {
		ctx.ft.draw_text(x, y, line.right(5), green_cfg)
		return
	}
	if line.contains('[31m') &&
	line.contains('FAIL') {
		ctx.ft.draw_text(x, y, line.right(5), red_cfg)
		return
	}
	// ctx.chunks = []Chunk{}
	ctx.chunks.len = 0
	for i := 0; i < line.len; i++ {
		start := i
		// Comment // #
		if i > 0 && line[i - 1] == `/` && line[i] == `/` {
			ctx.add_chunk(COMMENT, start - 1, line.len)
			break
		}
		if line[i] == `#` {
			ctx.add_chunk(COMMENT, start, line.len)
			break
		}
		// Comment   /*
		if i > 0 && line[i - 1] == `/` && line[i] == `*` {
			// All after /* is  a comment
			ctx.add_chunk(COMMENT, start, line.len)
			ctx.is_ml_comment = true
			break
		}
		// End of /**/
		if i > 0 && line[i - 1] == `*` && line[i] == `/` {
			// All before */ is still a comment
			ctx.add_chunk(COMMENT, 0, start + 1)
			ctx.is_ml_comment = false
			break
		}
		// String
		if line[i] == `\'` {
			i++
			// 39 == '
			for i < line.len - 1 && line[i] != `\'` {
				i++
			}
			if i >= line.len {
				i = line.len - 1
			}
			ctx.add_chunk(STRING, start, i + 1)
		}
		// Key
		for i < line.len && is_alpha_underscore(int(line[i])) {
			i++
		}
		word := line.substr(start, i)
		// println('word="$word"')
		if ctx.keys.contains(word) {
			// println('$word is key')
			ctx.add_chunk(KEY, start, i)
			// println('adding key. len=$ctx.chunks.len')
		}
	}
	if ctx.is_ml_comment {
		ctx.ft.draw_text(x, y, line, comment_cfg)
		return
	}
	if ctx.chunks.len == 0 {
		// println('no chunks')
		ctx.ft.draw_text(x, y, line, txt_cfg)
		return
	}
	mut pos := 0
	// println('"$line" nr chunks=$ctx.chunks.len')
	// TODO use runes
	// runes := msg.runes.slice_fast(chunk.pos, chunk.end)
	// txt := join_strings(runes)
	for i, chunk in ctx.chunks {
		// println('chunk #$i start=$chunk.start end=$chunk.end typ=$chunk.typ')
		// Initial text chunk (not initial, but the one right before current chunk,
		// since we don't have a seperate chunk for text)
		if chunk.start > pos + 1 {
			s := line.substr(pos, chunk.start)
			ctx.ft.draw_text(x + pos * ctx.char_width, y, s, txt_cfg)
		}
		// Keyword string etc
		mut cfg := txt_cfg
		typ := chunk.typ
		switch typ {
		case KEY:
			cfg = key_cfg
		case STRING:
			cfg = string_cfg
		case COMMENT:
			cfg = comment_cfg
		}
		s := line.substr(chunk.start, chunk.end)
		ctx.ft.draw_text(x + chunk.start * ctx.char_width, y, s, cfg)
		pos = chunk.end
		// Final text chunk
		if i == ctx.chunks.len - 1 && chunk.end < line.len {
			final := line.substr(chunk.end, line.len)
			ctx.ft.draw_text(x + pos * ctx.char_width, y, final, txt_cfg)
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
	// # printf("mouse click %p\n", glfw__Window_get_user_ptr(&wnd));
	// Mouse coords to x,y
	// ctx.view.y = pos.y / line_height - 1
	// ctx.view.x = (pos.x - ctx.view.padding_left) / char_width - 1
//}

// fn key_down(wnd * ui.Window, c char, mods int, code int) {
fn key_down(wnd *glfw.Window, key int, code int, action, mods int) {
	if action != 2 && action != 1 {
		return
	}
	// # printf("glfw vi.v key down key=%d key_char=%c code=%d action=%d mods=%d\n",
	// # key,key, code, action, mods);
	// single super
	if key == glfw.KEY_LEFT_SUPER {
		return
	}
	mut ctx := &Vid(glfw.get_window_user_pointer(wnd))
	mode := ctx.mode
	super := mods == 8 || mods == 2
	shift := mods == 1
	if key == glfw.KEY_ESCAPE {
		ctx.mode = NORMAL
	}
	// Reset error line
	mut view := ctx.view
	view.error_y = -1
	switch mode {
	case NORMAL:
		ctx.key_normal(key, super, shift)
	case VISUAL:
		ctx.key_visual(key, super, shift)
	case INSERT:
		ctx.key_insert(key, super)
	case QUERY:
		ctx.key_query(key, super)
	//case TIMER:
		//ctx.timer.key_down(key, super)
	}
}

fn on_char(wnd *glfw.Window, code u32, mods int) {
	mut ctx := &Vid(glfw.get_window_user_pointer(wnd))
	mode := ctx.mode
	if ctx.just_switched {
		ctx.just_switched = false
		return
	}
	buf := [0, 0, 0, 0, 0] ! 
	s := utf32_to_str_no_malloc(code,  buf.data) 
	//s := utf32_to_str(code)
	//println('s="$s" s0="$s0"') 
	switch mode {
	case INSERT:
		ctx.char_insert(s)
	case QUERY:
		ctx.gg_pos = -1
		ctx.char_query(s)
	case NORMAL:
		// on char on normal only for replace with r
		if !ctx.just_switched && ctx.prev_key == GLFW_KEY_R {
			if s != 'r' {
				ctx.view.r(s)
				ctx.prev_key = 0
				ctx.prev_cmd = 'r'
				ctx.prev_insert = s
			}
			return
		}
	}
}

fn (ctx mut Vid) key_query(key int, super bool) {
	switch key {
	case GLFW_KEY_BACKSPACE:
		ctx.gg_pos = -1
		if ctx.query_type != SEARCH && ctx.query_type != GREP {
			if ctx.query.len == 0 {
				return
			}
			ctx.query = ctx.query.left(ctx.query.len - 1)
		}
		else {
			if ctx.search_query.len == 0 {
				return
			}
			ctx.search_query = ctx.search_query.left(ctx.search_query.len - 1)
		}
		return
	case GLFW_KEY_ENTER:
		if ctx.query_type == CTRLP {
			ctx.ctrlp_open()
		}
		else if ctx.query_type == CAM {
			ctx.git_commit()
		}
		else if ctx.query_type == OPEN {
			ctx.view.open_file(ctx.query)
		}
		else if ctx.query_type == TASK {
			//ctx.timer.insert_task()
			//ctx.timer.cur_task = ctx.query
			//ctx.save_timer()
		}
		else if ctx.query_type == GREP {
			// Key down was pressed after typing, now pressing enter opens the file
			if ctx.gg_pos > -1 && ctx.gg_lines.len > 0 {
				line := ctx.gg_lines[ctx.gg_pos]
				path := line.all_before(':')
				line_nr := line.right(path.len + 1).int() -1
				ctx.view.open_file(ctx.workspace + '/' + path)
				ctx.view.move_to_line(line_nr)
				ctx.view.zz()
				ctx.mode = NORMAL
			}
			else {
				// Otherwise just do a git grep on a submitted query
				ctx.git_grep()
			}
			return
		}
		else {
			ctx.search(false)
		}
		ctx.mode = NORMAL
		return
	case GLFW_KEY_ESCAPE:
		ctx.mode = NORMAL
		return
	case GLFW_KEY_DOWN:
		if ctx.mode == QUERY && ctx.query_type == GREP {
			ctx.gg_pos++
		}
	case GLFW_KEY_TAB:// TODO COPY PASTA
		if ctx.mode == QUERY && ctx.query_type == GREP {
			ctx.gg_pos++
		}
	case GLFW_KEY_UP:
		if ctx.mode == QUERY && ctx.query_type == GREP {
			ctx.gg_pos--
			if ctx.gg_pos < 0 {
				ctx.gg_pos = 0
			}
		}
	case GLFW_KEY_V:
		if super {
			clip := ctx.main_wnd.get_clipboard_text()
			ctx.query = ctx.query + clip 
		}
	}
}

fn (ctx &Vid) is_in_blog() bool {
	return ctx.view.path.contains('/blog/') && ctx.view.path.contains('2019')
}

fn (ctx &Vid) git_commit() {
	text := ctx.query
	dir := ctx.workspace
	os.system('git -C $dir commit -am "$text"')
	//os.system('gitter $dir')
}

fn (ctx mut Vid) key_insert(key int, super bool) {
	switch key {
	case GLFW_KEY_BACKSPACE:
		ctx.view.backspace()
	case GLFW_KEY_ENTER:
		ctx.view.enter()
	case GLFW_KEY_ESCAPE:
		ctx.mode = NORMAL
	case GLFW_KEY_TAB:
		ctx.view.insert_text('\t')
	}
	if (key == GLFW_KEY_L || key == C.GLFW_KEY_S) && super {
		ctx.view.save_file()
		ctx.mode = NORMAL
		return
	}
	if super && key == GLFW_KEY_U {
		ctx.mode = NORMAL
		ctx.key_u()
		return
	}
	// Insert macro   TODO  customize
	if super && key == GLFW_KEY_G {
		ctx.view.insert_text('<code></code>')
		ctx.view.x -= 7
	}
	// Autocomplete
	if key == GLFW_KEY_N && super {
		ctx.ctrl_n()
		return
	}
	if key == GLFW_KEY_V && super {
		// ctx.view.insert_text(ui.get_clipboard_text())
		clip := ctx.main_wnd.get_clipboard_text()
		ctx.view.insert_text(clip)
		return
	}
}

fn (ctx mut Vid) ctrl_n() {
	line := ctx.view.line()
	mut i := ctx.view.x - 1
	end := i
	for i > 0 && is_alpha_underscore(int(line[i])) {
		i--
	}
	if !is_alpha_underscore(int(line[i])) {
		i++
	}
	mut word := line.substr(i, end + 1)
	word = word.trim_space()
	// Dont autocomplete if  fewer than 3 chars
	if word.len < 3 {
		return
	}
	for map_word in ctx.words {
		// If any word starts with our subword, add the rest
		if map_word.starts_with(word) {
			ctx.view.insert_text(map_word.right(word.len))
			return
		}
	}
}

fn (ctx mut Vid) key_normal(key int, super, shift bool) {
	mut view := ctx.view
	ctx.refresh = true
	if ctx.prev_key == GLFW_KEY_R {
		return
	}
	switch key {
		// Full screen => window
	case GLFW_KEY_ENTER:
		if false && super {
			ctx.nr_splits = 1
			ctx.win_width = 600
			ctx.win_height = 500
			glfw.post_empty_event()
		}
	case GLFW_KEY_PERIOD:
		if shift {
			// >
			ctx.view.shift_right()
		}
		else {
			ctx.dot()
		}
	case GLFW_KEY_COMMA:
		if shift {
			// <
			ctx.view.shift_left()
		}
	case GLFW_KEY_SLASH:
		if shift {
			ctx.search_query = ''
			ctx.mode = QUERY
			ctx.just_switched = true
			ctx.query_type = GREP
		}
		else {
			ctx.search_query = ''
			ctx.mode = QUERY
			ctx.just_switched = true
			ctx.query_type = SEARCH
		}
	case GLFW_KEY_F5:
		ctx.run_file()
		// ctx.char_width -= 1
		// ctx.line_height -= 1
		// ctx.font_size -= 1
		// ctx.page_height = WIN_HEIGHT / ctx.line_height - 1
		// case GLFW_KEY_F6:
		// ctx.char_width += 1
		// ctx.line_height += 1
		// ctx.font_size += 1
		// ctx.page_height = WIN_HEIGHT / ctx.line_height - 1
		// ctx.vg = gg.new_context(WIN_WIDTH, WIN_HEIGHT, ctx.font_size)
	case GLFW_KEY_MINUS:
		if super {
			ctx.get_git_diff_full()
		}
	case GLFW_KEY_EQUAL:
		ctx.open_blog()
	case GLFW_KEY_A:
		if super {
			ctx.query = ''
			ctx.mode = QUERY
			ctx.query_type = TASK
		}
		else {
			ctx.view.A()
			ctx.prev_cmd = 'A'
			ctx.set_insert()
		}
	case GLFW_KEY_C:
		if super {
			ctx.query = ''
			ctx.mode = QUERY
			ctx.query_type = CAM
		}
		if shift {
			ctx.prev_insert = ctx.view.C()
			ctx.set_insert()
		}
	case GLFW_KEY_D:
		if super {
			ctx.prev_split()
			return
		}
		if ctx.prev_key == GLFW_KEY_D {
			ctx.view.dd()
			return
		}
		else if ctx.prev_key == GLFW_KEY_G {
			ctx.go_to_def()
		}
	case GLFW_KEY_E:
		if super {
			ctx.next_split()
			return
		}
		if ctx.prev_key == GLFW_KEY_C {
			view.ce()
		}
		else if ctx.prev_key == GLFW_KEY_D {
			view.de()
		}
	case GLFW_KEY_I:
		if shift {
			ctx.view.I()
			ctx.set_insert()
			ctx.prev_cmd = 'I'
		}
		else {
			ctx.set_insert()
		}
	case GLFW_KEY_J:
		if shift {
			ctx.view.join()
		}
		else if super {
			// ctx.mode = QUERY
			// ctx.query_type = CTRLJ
		}
		else {
			// println('J isb=$ctx.is_building')
			ctx.view.j()
			// if !ctx.is_building {
			ctx.refresh = false
			// }
		}
	case GLFW_KEY_K:
		ctx.view.k()
		// if !ctx.is_building {
		ctx.refresh = false
		// }
	case GLFW_KEY_N:
		if shift {
			// backwards search
			ctx.search(true)
		}
		else {
			ctx.search(false)
		}
	case GLFW_KEY_O:
		if super {
			ctx.mode = QUERY
			ctx.query_type = OPEN
			ctx.query = ''
			return
		}
		else {
			ctx.view.o()
			ctx.set_insert()
		}
	case GLFW_KEY_P:
		if super {
			ctx.mode = QUERY
			ctx.query_type = CTRLP
			ctx.load_git_tree()
			return
		}
		else {
			view.p()
		}
	case GLFW_KEY_R:
		if super {
			view.reopen()
		}
		else {
			ctx.prev_key = GLFW_KEY_R
		}
	case GLFW_KEY_T:
		if super {
			//ctx.timer.get_data(false)
			//ctx.mode = TIMER
		}
		else {
			// if ctx.prev_key == GLFW_KEY_T {
			view.tt()
		}
	case GLFW_KEY_H:
		if shift {
			ctx.view.H()
		}
		else if ctx.view.x > 0 {
			ctx.view.x--
		}
	case GLFW_KEY_L:
		if super {
			ctx.view.save_file()
		}
		else if shift {
			ctx.view.move_to_page_bot()
		}
		else {
			ctx.view.l()
		}
	case GLFW_KEY_F6:
		if super {
		}
	case GLFW_KEY_G:
		// go to end
		if shift && !super {
			ctx.view.G()
		}
		// copy file path to clipboard
		else if super {
			ctx.main_wnd.set_clipboard_text(ctx.view.path)
		}
		// go to beginning
		else {
			if ctx.prev_key == GLFW_KEY_G {
				ctx.view.gg()
			}
		}
	case GLFW_KEY_F:
		if super {
			ctx.view.F()
		}
	case GLFW_KEY_B:
		if super {
			// force crash
			// # void*a = 0; int b = *(int*)a;
			ctx.view.B()
		}
		else {
			ctx.view.b()
		}
	case GLFW_KEY_U:
		if super {
			ctx.key_u()
		}
	case GLFW_KEY_V:
		ctx.mode = VISUAL
		view.vstart = view.y
		view.vend = view.y
	case GLFW_KEY_W:
		if ctx.prev_key == GLFW_KEY_C {
			view.cw()
		}
		else if ctx.prev_key == GLFW_KEY_D {
			view.dw()
		}
		else {
			view.w()
		}
	case GLFW_KEY_X:
		ctx.view.delete_char()
	case GLFW_KEY_Y:
		if ctx.prev_key == GLFW_KEY_Y {
			ctx.view.yy()
		}
		if super {
			go ctx.build_app2()
		}
	case GLFW_KEY_Z:
		if ctx.prev_key == GLFW_KEY_Z {
			ctx.view.zz()
		}
		// Next workspace
	case GLFW_KEY_RIGHT_BRACKET:
		if super {
			ctx.open_workspace(ctx.workspace_idx + 1)
		}
	case GLFW_KEY_LEFT_BRACKET:
		if super {
			ctx.open_workspace(ctx.workspace_idx - 1)
		}
	case GLFW_KEY_8:
		if shift {
			ctx.star()
		}
	}
	if key != GLFW_KEY_R {
		// otherwise R is triggered when we press C-R
		ctx.prev_key = key
	}
}

// Find current word under cursor
fn (ctx mut Vid) word_under_cursor() string {
	line := ctx.view.line()
	// First go left
	mut start := ctx.view.x
	for start > 0 && is_alpha_underscore(int(line[start])) {
		start--
	}
	// Now go right
	mut end := ctx.view.x
	for end < line.len && is_alpha_underscore(int(line[end])) {
		end++
	}
	mut word := line.substr(start + 1, end)
	word = word.trim_space()
	return word
}

fn (ctx mut Vid) star() {
	ctx.search_query = ctx.word_under_cursor()
	ctx.search(false)
}

fn (ctx mut Vid) char_insert(s string) {
	if int(s[0]) < 32 {
		return
	}
	ctx.view.insert_text(s)
	ctx.prev_insert = ctx.prev_insert + s 
}

fn (ctx mut Vid) char_query(s string) {
	if int(s[0]) < 32 {
		return
	}
	mut q := ctx.query
	if ctx.query_type == SEARCH || ctx.query_type == GREP {
		q = ctx.search_query
		ctx.search_query = '${q}${s}'
	}
	else {
		ctx.query = q + s 
	}
}

fn (ctx mut Vid) key_visual(key int, super, shift bool) {
	mut view := ctx.view
	switch key {
	case glfw.KEY_ESCAPE:
		ctx.exit_visual()
	case GLFW_KEY_J:
		view.vend++
		if view.vend >= view.lines.len {
			view.vend = view.lines.len - 1
		}
		// Scroll
		if view.vend >= view.from + view.page_height {
			view.from++
		}
	case GLFW_KEY_K:
		view.vend--
	case GLFW_KEY_Y:
		view.y_visual()
		ctx.mode = NORMAL
	case GLFW_KEY_D:
		view.d_visual()
		ctx.mode = NORMAL
	case GLFW_KEY_Q:
		if ctx.prev_key == GLFW_KEY_G {
			ctx.view.gq()
		}
	case GLFW_KEY_PERIOD:
		if shift {
			// >
			ctx.view.shift_right()
		}
	case GLFW_KEY_COMMA:
		if shift {
			// >
			ctx.view.shift_left()
		}
	}
	if key != GLFW_KEY_R {
		// otherwise R is triggered when we press C-R
		ctx.prev_key = key
	}
}

fn (ctx mut Vid) update_view() {
	ctx.view = &ctx.views[ctx.cur_split]
}

fn (ctx mut Vid) set_insert() {
	ctx.mode = INSERT
	ctx.prev_insert = ''
	ctx.just_switched = true
}

fn (ctx mut Vid) exit_visual() {
	ctx.mode = NORMAL
	mut view := ctx.view
	view.vstart = -1
	view.vend = -1
}

fn (ctx mut Vid) dot() {
	prev_cmd := ctx.prev_cmd
	switch prev_cmd {
	case 'dd':
		ctx.view.dd()
	case 'dw':
		ctx.view.dw()
	case 'cw':
		ctx.view.dw()
		// println('dot cw prev i=$ctx.prev_insert')
		ctx.view.insert_text(ctx.prev_insert)
		ctx.prev_cmd = 'cw'
	case 'de':
		ctx.view.de()
	case 'J':
		ctx.view.join()
	case 'I':
		ctx.view.I()
		ctx.view.insert_text(ctx.prev_insert)
	case 'A':
		ctx.view.A()
		ctx.view.insert_text(ctx.prev_insert)
	case 'r':
		ctx.view.r(ctx.prev_insert)
	}
}

fn (ctx mut Vid) next_split() {
	ctx.cur_split++
	if ctx.cur_split % ctx.splits_per_workspace == 0 {
		ctx.cur_split -= ctx.splits_per_workspace
	}
	ctx.update_view()
}

fn (ctx mut Vid) prev_split() {
	if ctx.cur_split % ctx.splits_per_workspace == 0 {
		ctx.cur_split += ctx.splits_per_workspace - 1
	}
	else {
		ctx.cur_split--
	}
	ctx.update_view()
}

fn (ctx mut Vid) open_workspace(idx int) {
	if idx >= ctx.workspaces.len {
		ctx.open_workspace(0)
		return
	}
	if idx < 0 {
		ctx.open_workspace(ctx.workspaces.len - 1)
		return
	}
	diff := idx - ctx.workspace_idx
	ctx.workspace_idx = idx
	ctx.workspace = ctx.workspaces[idx]
	// Update cur split index. If we are in space 0 split 1 and go to
	// space 1, split is updated to 4 (1 + 3 * (1-0))
	ctx.cur_split += diff * ctx.splits_per_workspace
	ctx.update_view()
	// ctx.get_git_diff()
}

fn (ctx mut Vid) add_workspace(path string) {
	// if ! os.file_exists(path) {
	// ui.alert('"$path" doesnt exist')
	// }
	ctx.workspaces << path 
	for i := 0; i < ctx.nr_splits; i++ {
		ctx.views << ctx.new_view() 
	}
}

fn short_space(workspace string) string {
	pos := workspace.last_index('/')
	if pos == -1 {
		return workspace
	}
	return workspace.right(pos + 1)
}

fn (ctx &Vid) move_to_line(n int) {
	mut view := ctx.view
	view.from = n
	view.y = n
}

fn (ctx &Vid) save_session() {
	println('saving session...')
	f := os.create(SESSION_PATH) or { panic('fail') }
	for view in ctx.views {
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
fn toi(s string) int {
	return s.int()
}

fn (ctx &Vid) save_timer() {
/* 
	f := os.create(TIMER_PATH) or { return }
	f.writeln('task=$ctx.timer.cur_task')
	f.writeln('task_start=$ctx.timer.task_start_unix')
	f.writeln('timer_typ=$ctx.timer.cur_type')
	if ctx.timer.started {
		f.writeln('timer_start=$ctx.timer.start_unix')
	}
	else {
		f.writeln('timer_start=0')
	}
	f.close()
*/ 
}

fn (ctx mut Vid) load_timer() {
	// task=do work
	// task_start=1223212221
	// timer_typ=7
	// timer_start=12321321
/* 
	lines := os.read_lines(TIMER_PATH)
	if lines.len == 0 {
		return
	}
	println(lines)
	mut vals := []string
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
	println('vals=')
	println(vals)
	ctx.timer.cur_task = vals[0]
	ctx.timer.task_start_unix = toi(vals[1])
	ctx.timer.cur_type = toi(vals[2])
	ctx.timer.start_unix = toi(vals[3])
	ctx.timer.started = ctx.timer.start_unix != 0
*/ 
}

fn (ctx mut Vid) load_session() {
	println('load session "$SESSION_PATH"')
	paths := os.read_lines(SESSION_PATH)
	println(paths)
	ctx.load_views(paths)
}

fn (ctx mut Vid) load_views(paths[]string) {
	for i := 0; i < paths.len && i < ctx.views.len; i++ {
		// println('loading path')
		// println(paths[i])
		mut view := &ctx.views[i]
		path := paths[i]
		if path == '' || path.contains('=') {
			continue
		}
		view.open_file(path)
	}
}

fn (ctx mut Vid) get_git_diff() {
	return
	/* 
	dir := ctx.workspace
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
	ctx.git_diff_plus = '$plus+'
	if vals.len < 3 {
		return
	}
	mut minus := vals[2]
	minus = minus.find_between(' ', 'deletion')
	minus = minus.trim_space()
	ctx.git_diff_minus = '$minus-'
*/
}

fn (ctx &Vid) get_git_diff_full() string {
	dir := ctx.workspace
	os.system('git -C $dir diff > $dir/out')
	mut last_view := ctx.get_last_view()
	last_view.open_file('$dir/out')
	// nothing commited (diff = 0), shot git log)
	if last_view.lines.len < 2 {
		// os.system('echo "no diff\n" > $dir/out')
		os.system(
		'git -C $dir log -n 20 --pretty=format:"%%ad %%s" --simplify-merges --date=format:"%%Y-%%m-%%d %%H:%%M:%%S    "> $dir/out')
		last_view.open_file('$dir/out')
	}
	last_view.gg()
	return 's'
}

fn (ctx &Vid) open_blog() {
	now := time.now()
	dir := 'blog' 
	path := '$dir/$now.year/${now.month:02d}/${now.day:02d}'
	if !os.file_exists(path) {
		os.system('touch $path')
	}
	mut last_view := ctx.get_last_view()
	last_view.open_file(path)
	last_view.G()
}

fn (ctx &Vid) get_last_view() *View {
	pos := (ctx.workspace_idx + 1) * ctx.splits_per_workspace - 1
	return &ctx.views[pos]
}

fn (ctx mut Vid) build_app1() {
	ctx.build_app('')
}

fn (ctx mut Vid) build_app2() {
	ctx.build_app('2')
}

fn (ctx mut Vid) save_changed_files() {
	for _view in ctx.views {
		mut view := _view
		if view.changed {
			view.save_file()
		}
	}
}

fn (ctx mut Vid) build_app(extra string) {
	ctx.is_building = true
	println('building...')
	// Save each open file before building
	ctx.save_changed_files()
	os.chdir(ctx.workspace)
	dir := ctx.workspace
	mut last_view := ctx.get_last_view()
	//mut f := os.create('$dir/out') or {
		//panic('ff')
		//return
	//}
	last_view.open_file('$dir/out')
	out := os.exec('sh $dir/build$extra') or {
		return
	}
	f2 := os.create('$dir/out') or {
		panic('fail')
	}
	f2.writeln(out)
	f2.close()
	last_view.open_file('$dir/out')
	last_view.G()
	// error line
	lines := out.split_into_lines()
	for line in lines {
		if line.contains('.v:') {
			ctx.go_to_error(line)
			break
		}
	}
	// ctx.refresh = true
	glfw.post_empty_event()
	time.sleep(4)// delay is_building to prevent flickering in the right split
	ctx.is_building = false
	return
	// Reopen files (they were formatted)
	for _view in ctx.views {
		// ui.alert('reopening path')
		mut view := _view
		println(view.path)
		view.open_file(view.path)
	}
}

// Run file in current view (go run [file], v run [file], python [file] etc)
// Saves time for user since they don't have to define 'build' for every file
fn (ctx mut Vid) run_file() {
	mut view := ctx.view
	ctx.is_building = true
	println('start file run')
	// Save the file before building
	if view.changed {
		view.save_file()
	}
	// go run /a/b/c.go
	// dir is "/a/b/"
	// cd to /a/b/
	// dir := ospath.dir(view.path)
	pos := view.path.last_index('/')
	dir := view.path.left(pos)
	os.chdir(dir)
	out := os.exec('v $view.path') or { return }
	f := os.create('$dir/out') or { panic('foo') } 
	f.writeln(out)
	f.close()
	// TODO COPYPASTA
	mut last_view := ctx.get_last_view()
	last_view.open_file('$dir/out')
	last_view.G()
	ctx.is_building = false
	// error line
	lines := out.split_into_lines()
	for line in lines {
		if line.contains('.v:') {
			ctx.go_to_error(line)
			break
		}
	}
	ctx.refresh = true
	glfw.post_empty_event()
}

fn (ctx mut Vid) go_to_error(line string) {
	// panic: volt/twitch.v:88
	println('go to ERROR $line')
	//if !line.contains('panic:') {
		//return
	//}
	line = line.replace('panic: ', '')
	pos := line.index(':')
	if pos == -1 {
		println('no 2 :')
		return
	}
	path := line.left(pos)
	filename := path.all_after('/')
	line_nr := line.right(pos + 1)
	for i := 0; i < ctx.views.len; i++ {
		mut view := &ctx.views[i]
		if !view.path.contains(filename) {
			continue
		}
		view.error_y = line_nr.int() -1
		view.move_to_line(view.error_y)
		// view.ctx.main_wnd.refresh()
		glfw.post_empty_event()
		break// Done after the first view with the error
	}
	// File with the error is not open right now, do it
	s := os.exec('git -C $ctx.workspace ls-files') or { return }
	mut lines := s.split_into_lines()
	lines.sort_by_len()
	for _ in lines {
		if line.contains(filename) {
			ctx.view.open_file(ctx.workspace + '/' + line)
			ctx.view.error_y = line_nr.int() -1
			ctx.view.move_to_line(ctx.view.error_y)
			glfw.post_empty_event()
			return
		}
	}
}

fn (ctx mut Vid) loop() {
	for {
		ctx.refresh = true
		glfw.post_empty_event()
		//ctx.timer.tick(ctx)
		time.sleep(5)
	}
}

fn (ctx mut Vid) key_u() {
	// Run a single test file
	if ctx.view.path.ends_with('_test.v') {
		ctx.run_file()
	}
	else {
		go ctx.build_app1()
		glfw.post_empty_event()
	}
}

fn (ctx mut Vid) go_to_def() {
	word := ctx.word_under_cursor()
	query := ') $word'
	mut view := ctx.view
	for i, line in view.lines {
		if line.contains(query) {
			ctx.move_to_line(i)
			return
		}
	}
	// Not found in current file, try all files in the git tree 
	for _file in ctx.all_git_files { 
		mut file := _file.to_lower()
		file = file.trim_space()
		if !file.ends_with('.v') {
			continue
		}
		file = '$ctx.workspace/$file'
		lines := os.read_lines(file)
		// println('trying file $file with $lines.len lines')
		for j, line in lines {
			if line.contains(query) {
				view.open_file(file)
				ctx.move_to_line(j)
				break
			}
		}
	}
}

fn segfault_sigaction(signal int, si voidptr, arg voidptr) {
	println('crash!')
	/*
	mut ctx := &Vid{!}
	//# ctx=g_ctx;
	# ctx=arg;
	println(ctx.line_height)
	// ctx.save_session()
	// ctx.save_timer()
	ctx.save_changed_files()
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

fn (ctx mut Vid) handle_segfault() {
	$if windows {
		return
	}
	/*
	# g_ctx= ctx ;
	# struct sigaction sa;
	# int *foo = NULL;
	# memset(&sa, 0, sizeof(struct sigaction));
	# sigemptyset(&sa.sa_mask);
	# sa.sa_sigaction = segfault_sigaction;
	# sa.sa_flags   = SA_SIGINFO;
	# sigaction(SIGSEGV, &sa, 0);
	*/
}

