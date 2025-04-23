// Copyright (c) 2019-2023 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import gg
import gx
import os
import time
import uiold
import clipboard
import json

const exe_dir = os.dir(os.executable())
const home_dir = os.home_dir()
const settings_dir = os.join_path(home_dir, '.ved')
const codeblog_path = os.join_path(home_dir, 'code', 'blog')
const syntax_dir = os.join_path(settings_dir, 'syntax')
const session_path = os.join_path(settings_dir, 'session')
const workspaces_path = os.join_path(settings_dir, 'workspaces')
const timer_path = os.join_path(settings_dir, 'timer')
const tasks_path = os.join_path(settings_dir, 'tasks')
const config_path = os.join_path(settings_dir, 'conf.toml')
const config_path2 = os.join_path(settings_dir, 'config.json')
const max_nr_workspaces = 10

@[heap]
struct Ved {
mut:
	win_width          int
	win_height         int
	nr_splits          int
	page_height        int
	views              []View
	cur_split          int
	view               &View = unsafe { nil }
	mode               EditorMode
	just_switched      bool // for keydown/char events to avoid dup keys
	prev_key           gg.KeyCode
	prev_key_str       string // for `ci(` etc, no `(` in gg.KeyCode
	prev_cmd           string
	prev_insert        string // for `.` (re-enter the text that was just entered via cw etc)
	all_git_files      []string
	top_tasks          []string
	gg                 &gg.Context = unsafe { nil }
	query              string
	search_query       string
	query_type         QueryType
	workspace          string // full path of the current workspace (a short version of it is rendered on otp right)
	workspace_idx      int
	workspaces         []string
	ylines             []string // for y, yy
	git_diff_plus      string   // short git diff stat top right
	git_diff_minus     string
	syntaxes           []Syntax
	current_syntax_idx int
	chunks             []Chunk
	is_building        bool
	timer              Timer
	task_start_unix    i64
	cur_task           string
	words              []string
	file_y_pos         map[string]int // to save current line for each file s
	refresh            bool = true
	char_width         int
	is_ml_comment      bool
	gg_lines           []string
	gg_pos             int
	cfg                Config
	cb                 &clipboard.Clipboard = unsafe { nil }
	open_paths         [][]string // all open files (tabs) per workspace: open_paths[workspace_idx] == ['a.txt', b.v']
	prev_y             int        // for jumping back ('')
	now                time.Time  // cached value of time.now() to avoid calling it for every frame
	search_history     []string
	search_idx         int
	cq_in_a_row        int
	search_dir         string // for cmd+/ search in the entire directory where the current file is located
	search_dir_idx     int    // for looping thru search dir files
	error_line         string // is displayed at the bottom
	autocomplete_info  AutocompleteInfo
	autocomplete_cache map[string][]AutocompleteField // autocomplete_cache["v.checker.Checker"] == [{"AnonFn", "void"}, {"cur_anon_fn", "AnonFn"}]
	debug_info         string
	debugger           Debugger
	cur_fn_name        string              // Always displayed on the top bar
	grep_file_exts     map[string][]string // m['workspace_path'] == ['v', 'go']
	// debugger_output      DebuggerOutput
	tree Tree // for rendering file tree on the left
}

// From parsed workspace/path/.ved json file
struct Workspace {
	grep_file_extensions []string
	// path string
}

// For syntax highlighting
enum ChunkKind {
	a_string  = 1
	a_comment = 2
	a_key     = 3
	a_lit     = 4
}

enum EditorMode {
	normal       = 0
	insert       = 1
	query        = 2
	visual       = 3
	timer        = 4
	autocomplete = 5
	debugger     = 6
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

const help_text = '
Usage: ved [options] [files]

Options:
  -h, --help              Display this information.
  -window <window-name>   Launch in a window.
  -dark                   Launch in dark mode.
  -two_splits
'

const fpath = os.resource_abs_path('RobotoMono-Regular.ttf')
const args = os.args.clone()
const is_window = '-window' in args

fn get_screen_size() (int, int) {
	mut size := gg.screen_size()
	println('AAA SIZE=${size}')
	if true {
		// exit(0)
	}
	if size.width == 0 || size.height == 0 {
		size = $if small_window ? { gg.Size{770, 480} } $else { gg.Size{2560, 1440} }
	}
	// Fix macbook notch crap
	$if macos {
		if size.height % 20 != 0 {
			// size.height -= size.height % 20 + ved.cfg.line_height
			size.height -= 32 // ved.cfg.line_height
		}
	}
	println('size=${size}')
	return size.width, size.height
}

@[console]
fn main() {
	if '-h' in args || '--help' in args {
		println(help_text)
		return
	}
	if !os.is_dir(settings_dir) {
		os.mkdir(settings_dir) or { panic(err) }
	}
	width, height := get_screen_size()
	mut ved := &Ved{
		win_width:  width
		win_height: height
		// nr_splits: nr_splits
		// nr_splits: nr_splits
		cur_split:  0
		mode:       .normal
		cb:         clipboard.new()
		open_paths: [][]string{len: max_nr_workspaces}
	}
	ved.handle_segfault()

	// ved.cfg.set_settings(config_path)
	println('CONFIG')
	println(ved.cfg)
	ved.load_config2()

	ved.nr_splits = ved.get_nr_splits_from_screen_size(width, height)
	ved.calc_nr_splits_from_text_size()
	println('splits per w = ${ved.nr_splits}')

	println('height=${height}')

	ved.load_syntaxes()

	ved.gg = gg.new_context(
		width:         width
		height:        height // borderless_window: !is_window
		fullscreen:    !is_window
		window_title:  'Ved'
		create_window: true
		user_data:     ved
		scale:         2
		bg_color:      ved.cfg.bgcolor
		frame_fn:      frame
		on_event:      ved.on_event
		keydown_fn:    key_down
		char_fn:       on_char
		font_path:     fpath
		ui_mode:       true
	)
	println('full screen=${!is_window}')
	ved.timer = new_timer(mut ved.gg)
	ved.load_all_tasks()
	// TODO linux and windows
	// C.AXUIElementCreateApplication(234)
	uiold.reg_key_ved()
	// Open workspaces or a file
	$if debug {
		println('args:')
		println(args)
	}
	mut cur_dir := os.getwd()
	if cur_dir.ends_with('/ved.app/Contents/Resources') {
		cur_dir = cur_dir.replace('/ved.app/Contents/Resources', '')
	}
	mut first_launch := false
	if args.len == 1 {
		// No args, open previous saved workspaces.
		if workspaces := os.read_lines(workspaces_path) {
			for workspace in workspaces {
				ved.add_workspace(workspace)
			}
		} else {
			first_launch = true
			ved.add_workspace('.')
		}
		ved.open_workspace(0)
	}
	// Open a single text file
	else if args.len == 2 && os.is_file(args.last()) {
		path := args[args.len - 1]
		if !os.exists(path) {
			println('file "${path}" does not exist')
			exit(1)
		}
		println('PATH="${path}" cur_dir="${cur_dir}"')
		if !os.is_dir(path) && !path.starts_with('-') {
			mut workspace := os.dir(path)
			ved.add_workspace(workspace)
			ved.open_workspace(0)
			ved.view.open_file(path, 0)
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
	ved.grep_file_exts = read_grep_file_exts(ved.workspaces)
	ved.load_session()
	ved.load_timer()
	ved.init_tree()
	println('first_launch=${first_launch}')
	if ved.workspaces.len == 1 && first_launch && !os.exists(session_path) {
		ved.view.open_file(os.join_path(exe_dir, 'welcome.txt'), 0)
	}
	spawn ved.loop()
	ved.refresh = true
	ved.gg.run()
}

fn (mut ved Ved) on_event(e &gg.Event) {
	// println('on_event ${ved.win_width}')
	ved.refresh = true
	/*
	// TODO change win height/width only on cmd + enter (exit full screen etc)
	mut size := gg.screen_size()

	// Fix macbook notch crap
	$if macos {
		if size.height % 20 != 0 {
			// size.height -= size.height % 20 + ved.cfg.line_height
			size.height -= 32 // ved.cfg.line_height
		}
	}
	ved.win_height = size.height
	ved.win_width = size.width
	*/

	if e.typ == .mouse_scroll {
		if e.scroll_y < -0.2 {
			ved.view.j()
		} else if e.scroll_y > 0.2 {
			ved.view.k()
		}
	}

	// FIXME: The rounding math here cause the Y coord to be unintuitive sometimes.
	if e.typ == .mouse_down {
		if ved.cfg.disable_mouse {
			return
		}

		mut view := ved.view

		mut current_line := ''
		if view.y > 0 && view.y < view.lines.len {
			current_line = view.lines[view.y]
		}
		current_line_split := current_line.split('\t')
		mut leading_tabs := 0
		for i := 0; i < current_line_split.len; i++ {
			if current_line_split[i] == '' {
				leading_tabs++
			}
		}

		// Focus the pane currently under the cursor before continuing
		for i := 0; i < ved.nr_splits; i++ {
			sw := ved.split_width()
			starting_x := 2 * i * sw
			ending_x := 2 * (i + 1) * sw

			if e.mouse_x > starting_x && e.mouse_x < ending_x {
				ved.cur_split = i
				ved.update_view()
			}
		}

		clicked_y := int((e.mouse_y / ved.cfg.line_height - 1.5) / 2) + ved.view.from
		if clicked_y >= view.lines.len {
			if view.lines.len == 0 {
				view.set_y(0)
			} else {
				view.set_y(view.lines.len - 1)
			}
		} else if clicked_y < 0 {
			view.set_y(1)
		} else {
			view.set_y(clicked_y)
		}

		// Wow, that's a lot of math that is probably pretty hard to parse.
		// In the future I need to separate this into several variables,
		// and perhaps even its own function.
		clicked_x := int(((e.mouse_x - ved.cur_split * ved.split_width() * 2 - view.padding_left) / ved.cfg.char_width) / 2 - 3 - leading_tabs * 3)
		if view.lines.len <= 0 {
			return
		}
		if clicked_x > view.lines[view.y].len {
			view.x = view.lines[view.y].len
		} else if clicked_x < 0 {
			view.x = 0
		} else {
			view.x = clicked_x
		}
	}
}

fn (ved &Ved) split_width() int {
	mut split_width := ved.win_width / ved.nr_splits // + 60
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

/*
fn (ved &Ved) is_in_blog() bool {
	return ved.view.path.contains('/blog/') && ved.view.path.contains('20')
}
*/

fn (ved &Ved) git_commit() {
	text := ved.query
	dir := ved.workspace
	os.system('git -C ${dir} commit -am "${text}"')
	// os.system('gitter $dir')
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

// Find current word under cursor
fn (ved &Ved) word_under_cursor() string {
	line := ved.view.line()
	// First go left
	mut start := ved.view.x
	if start > 0 && line.len > 0 && !is_alpha_underscore(int(line[start - 1])) {
		return ''
	}
	for start > 0 && is_alpha_underscore(int(line[start])) {
		start--
	}
	// Now go right
	mut end := ved.view.x
	for end < line.len && is_alpha_underscore(int(line[end])) {
		end++
	}
	if start + 1 >= line.len || start >= end {
		return ''
	}
	// println("word under cursor line='$line' start=$start end=$end")
	// print_backtrace()
	mut word := line[start + 1..end]
	word = word.trim_space()
	return word
}

// used only when pressing dot in insert mode and showing the autocomplete window
fn (ved &Ved) word_under_cursor_no_right() string {
	line := ved.view.line()
	mut start := ved.view.x - 1
	// println('\n\n1line="${line}" linelen=${line.len} start=${start} s="${line[start..]}"')
	// println("C='${line[start]}'")
	for start > 0 && is_alpha_underscore(int(line[start])) {
		// println('minus')
		start--
	}
	// println('new start=${start}')
	mut word := line[start + 1..line.len]
	word = word.trim_space()
	return word
}

fn (mut ved Ved) star() {
	ved.search_query = ved.word_under_cursor()
	ved.search(.forward)
}

// switch between { and } etc
fn (mut ved Ved) pct() {
	mut line := ved.view.line()
	if ved.view.x >= line.len {
		return
	}
	c := line[ved.view.x]
	if c !in [`{`, `}`, `[`, `]`, `(`, `)`] {
		return
	}
	opposite_c := match c {
		`{` { `}` }
		`}` { `{` }
		`[` { `]` }
		`]` { `[` }
		`(` { `)` }
		`)` { `(` }
		else { ` ` }
	}
	going_up := c in [`}`, `]`, `)`]
	mut x := 0
	mut line_nr := ved.view.y
	mut stack := 0
	// for line_nr >= 1 {
	for {
		if going_up {
			line_nr--
			if line_nr < 0 {
				break
			}
		} else {
			line_nr++
			if line_nr >= ved.view.lines.len {
				break
			}
		}

		line = ved.view.lines[line_nr]
		// for x >= 1 {
		if going_up {
			x = line.len
		} else {
			x = -1
		}
		// TODO handle {} in strings and comments
		for {
			if going_up {
				x--
				if x < 0 {
					break
				}
			} else {
				x++
				if x >= line.len {
					break
				}
			}
			if line[x] == c {
				stack++
			} else if line[x] == opposite_c {
				// println('GOT $oppsoite_c stack=${stack} line_nr=${line_nr} x=${x}')
				if stack == 0 {
					// If the char we need to move to is on the same page, just update view.y
					// otherwise move to that line and zz (TODO maybe move this to a separate method)
					if line_nr >= ved.view.from && line_nr <= ved.view.from + ved.page_height {
						ved.view.y = line_nr
					} else {
						ved.move_to_line(line_nr)
						ved.view.zz()
					}
					// Set the col as well
					ved.view.x = x
					return
				} else {
					stack--
				}
			}
		}
	}
}

fn (mut ved Ved) update_view() {
	$if debug {
		println('update view len=${ved.views.len}')
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
			ved.view.dw(false)
			// println('dot cw prev_insert=$ved.prev_insert')
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
	if ved.cur_split % ved.nr_splits == 0 {
		ved.cur_split -= ved.nr_splits
	}
	ved.update_cur_fn_name()
	ved.update_view()
}

fn (mut ved Ved) prev_split() {
	if ved.cur_split % ved.nr_splits == 0 {
		ved.cur_split += ved.nr_splits - 1
	} else {
		ved.cur_split--
	}
	ved.update_cur_fn_name()
	ved.update_view()
}

fn (mut ved Ved) open_workspace(idx int) {
	//$if debug {
	println('open workspace(${idx})')
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
	ved.cur_split += diff * ved.nr_splits

	for i, view in ved.views {
		// Maybe the file is not loaded correctly (can happen on ved's launch)
		// Try to re-open it
		if view.lines.len < 2 && view.path != '' {
			ved.views[i].open_file(view.path, ved.view.y)
		}
	}
	ved.update_view()
	// ved.get_git_diff()
}

fn (mut ved Ved) add_workspace(path string) {
	//$if debug {
	println('add_workspace("${path}")')
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
	return workspace[pos + 1..].limit(10)
}

fn (mut ved Ved) move_to_line(n int) {
	ved.prev_y = ved.view.y
	ved.view.from = n
	ved.view.set_y(n)
}

fn (ved &Ved) save_session() {
	println('saving session...')
	mut f := os.create(session_path) or { panic('fail') }
	for _, view in ved.views {
		// println('saving view #${i} ${view.path}')
		// if view.path == '' {
		// continue
		// }
		if view.path == 'out' {
			continue
		}
		f.writeln('${view.path}:${view.y}') or { panic(err) }
	}
	f.close()
	mut f_workspace := os.create(workspaces_path) or { panic(err) }
	for workspace in ved.workspaces {
		f_workspace.writeln(workspace) or { panic(err) }
	}
	f_workspace.close()
}

// TODO fix vals[0].int()
fn toi(s string) i64 {
	return s.i64()
}

fn (ved &Ved) save_timer() {
	mut f := os.create(timer_path) or { return }
	f.writeln('task=${ved.cur_task}') or { panic(err) }
	f.writeln('task_start=${ved.task_start_unix}') or { panic(err) }
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
	println('load session "${session_path}"')
	paths := os.read_lines(session_path) or { return }
	println(paths)
	ved.load_views(paths)
}

fn (mut ved Ved) load_views(paths []string) {
	for i := 0; i < paths.len && i < ved.views.len; i++ {
		// println('loading path')
		// println(paths[i])
		// mut view := &ved.views[i]
		mut path := paths[i]
		mut line_nr := 0
		if path == '' || path.contains('=') {
			continue
		}
		if path.contains(':') {
			// myfile.v:23
			// can contain line numbers from the previous session, parse them and go to them
			vals := path.split(':')
			path = vals[0]
			line_nr = vals[1].int()
		}
		// view.open_file(path)
		ved.views[i].open_file(path, line_nr)
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
	os.system('git -C ${dir} diff > ${dir}/out')
	mut last_view := ved.get_last_view()
	last_view.open_file('${dir}/out', 0)
	// nothing commited (diff = 0), shot git log)
	if last_view.lines.len < 2 {
		// os.system('echo "no diff\n" > $dir/out')
		os.system('git -C ${dir} log -n 40 --pretty=format:"%ad %s" ' +
			'--simplify-merges --date=format:"%Y-%m-%d %H:%M  "> ${dir}/out')
		last_view.open_file('${dir}/out', 0)
	}
	last_view.gg()
	return 's'
}

fn (mut ved Ved) open_blog() {
	now := time.now()
	path := os.join_path(codeblog_path, '${now.year}', '${now.month:02d}', '${now.day:02d}')
	parent_dir := os.dir(path)
	parent_dir2 := os.dir(parent_dir)
	if !os.exists(parent_dir2) {
		os.mkdir(parent_dir2) or { panic(err) }
	}
	if !os.exists(parent_dir) {
		os.mkdir(parent_dir) or { panic(err) }
	}
	if !os.exists(path) {
		os.system('touch ${path}')
	}
	mut last_view := ved.get_last_view()
	last_view.open_file(path, 0)
	last_view.gg()
	// last_view.shift_g()
	// Go to the opened blog (TODO must be an easier way)
	for i := 0; i < 5; i++ {
		if ved.view.path == path {
			break
		}
		ved.next_split()
	}
}

fn (ved &Ved) get_last_view() &View {
	pos := (ved.workspace_idx + 1) * ved.nr_splits - 1
	eprintln('> ${@METHOD} pos: ${pos}')
	unsafe {
		return &ved.views[pos]
	}
}

fn (ved &Ved) last_view_idx() int {
	return (ved.workspace_idx + 1) * ved.nr_splits - 1
}

fn (mut ved Ved) save_changed_files() {
	for i, view in ved.views {
		if view.changed {
			ved.views[i].save_file()
		}
	}
}

fn (mut ved Ved) get_build_file_location() ?string {
	dir := ved.workspace
	mut build_file := '${dir}/build'
	if !os.exists(build_file) {
		build_file = '${dir}/.ved/build'
		if !os.exists(build_file) {
			return none
		}
	}
	return build_file
}

fn (mut ved Ved) go_to_error(line string, error_details string) {
	ved.error_line = line.after('error: ')
	ved.error_line += '    ' + error_details
	// panic: volt/twitch.v:88
	println('go to ERROR line="${line}" error_details=${error_details}')
	// line = line.replace('panic: ', '')
	vals := line.split(':')
	println('vals=${vals}')
	if vals.len < 4 {
		return
	}
	mut filename := vals[0]
	if filename.starts_with('./') {
		filename = filename[2..]
	}
	ext := os.file_ext(filename)
	println('ext="${ext}"')
	pos := line.index(ext + ':') or {
		println('no 2 :')
		return
	}
	path := line[..pos]
	line_nr := vals[1].int()
	col := vals[2].int()
	println('path=${path} filename=${filename} linenr=${line_nr} col=${col}')
	// Search for the file with the eror in all views inside current workspace
	start_i := ved.workspace_idx * ved.nr_splits
	end_i := (ved.workspace_idx + 1) * ved.nr_splits
	for i := start_i; i < end_i && i < ved.views.len; i++ {
		mut view := unsafe { &ved.views[i] }
		if !view.path.contains(os.path_separator + filename) && view.path != filename {
			continue
		}
		view.error_y = line_nr - 1
		println('i=${i} view.path=${view.path} error_y=${view.error_y} ')
		view.move_to_line(view.error_y)
		if col > 0 {
			view.x = col - 1
		}
		// view.ved.main_wnd.refresh()
		// Done after the first view with the error
		return
	}
	println('file with error not found (not open), running git ls-files')
	// File with the error is not open right now, do it
	s := os.execute('git -C ${ved.workspace} ls-files')
	if s.exit_code == -1 {
		return
	}
	mut lines := s.output.split_into_lines()
	lines.sort_by_len()
	for git_file in lines {
		if git_file.contains(filename) {
			ved.view.open_file(git_file, ved.view.error_y) // ved.workspace + '/' + line)
			ved.view.error_y = line_nr - 1
			ved.view.move_to_line(ved.view.error_y)
			if col > 0 {
				ved.view.x = col - 1
			}
			return
		}
	}
}

fn (mut ved Ved) loop() {
	for {
		ved.refresh = true
		ved.now = time.now()
		ved.gg.refresh_ui()
		// ved.timer.tick(ved)
		time.sleep(5 * time.second)
		if ved.timer.pom_is_started && ved.now.unix() - ved.timer.pom_start > 25 * 60 {
			ved.timer.pom_is_started = false
			lock_screen()
		}
	}
}

fn (mut ved Ved) key_u() {
	// Run a single test file
	if ved.view.path.ends_with('_test.v') {
		ved.run_file()
	} else {
		ved.refresh = true
		spawn ved.build_app1()
	}
}

fn segfault_sigaction(signal int, si voidptr, arg voidptr) {
	println('crash!')
	/*
	mut ved := &Ved{!}
	//# ved=g_ved;
	# ved=arg;
	println(ved.cfg.line_height)
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
	# g_ved= ctx ;
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
	mut seconds := ved.now.unix() - ved.task_start_unix
	if ved.task_start_unix <= 0 {
		seconds = 0
	}
	return int(seconds / 60)
}

fn (mut ved Ved) git_pull() {
	os.system('git -C "${ved.workspace}" pull --rebase')
	ved.mode = .normal
	ved.gg.refresh_ui()
}

const text_scale = 1.2

const max_text_size = 24
const min_text_size = 18

fn (mut ved Ved) increase_font(delta int) {
	// println('INCREASE_FONT(${delta})')
	// println('text_size=${ved.cfg.text_size}')
	// println('char_width=${ved.cfg.char_width}')
	// println('line_height=${ved.cfg.line_height}')
	ved.cfg.text_size += delta * 2
	if ved.cfg.text_size > max_text_size {
		ved.cfg.text_size = max_text_size
		return
	}
	if ved.cfg.text_size < min_text_size {
		ved.cfg.text_size = min_text_size
		return
	}
	ved.cfg.char_width += delta
	// ved.cfg.char_width = ved.cfg.text_size - 10
	ved.cfg.line_height = ved.cfg.text_size + 2
	// x := ved.cfg.txt_cfg
	ved.cfg.txt_cfg = gx.TextCfg{
		...ved.cfg.txt_cfg
		size: ved.cfg.text_size
	}
	ved.cfg.comment_cfg = gx.TextCfg{
		...ved.cfg.comment_cfg
		size: ved.cfg.text_size
	}
	ved.cfg.key_cfg = gx.TextCfg{
		...ved.cfg.key_cfg
		size: ved.cfg.text_size
	}
	ved.cfg.line_nr_cfg = gx.TextCfg{
		...ved.cfg.line_nr_cfg
		size: ved.cfg.text_size
	}
	ved.cfg.string_cfg = gx.TextCfg{
		...ved.cfg.string_cfg
		size: ved.cfg.text_size
	}
	ved.cfg.file_name_cfg = gx.TextCfg{
		...ved.cfg.file_name_cfg
		size: ved.cfg.text_size
	}
	// println('NEW text_size=${ved.cfg.text_size}')
	// println('NEW char_width=${ved.cfg.char_width}')
	// println('NEW line_height=${ved.cfg.line_height}\n')
	ved.calc_nr_splits_from_text_size()
	ved.save_config2()
	// println('NEW  CONFIG')
	// println(ved.cfg)
}

fn (mut ved Ved) calc_nr_splits_from_text_size() {
	if ved.cfg.text_size > 20 && ved.nr_splits > 2 {
		ved.nr_splits = 2
	} else if ved.cfg.text_size <= 20 {
		ved.nr_splits = ved.get_nr_splits_from_screen_size(ved.win_width, ved.win_height)
	}
}

fn filter_ascii_colors(s string) string {
	return s.replace_each(['[22m', '', '[35m', '', '[39m', '', '[1m', '', '[31m', ''])
}

fn (ved &Ved) get_nr_splits_from_screen_size(width int, height int) int {
	println('screen_width=${width}')
	mut nr_splits := 3
	if '-two_splits' in args || width < 1800 {
		nr_splits = 2
	}
	if is_window || '-laptop' in args {
		nr_splits = 1
	}
	max_split_width := ved.cfg.char_width * 110
	println('MAX=${max_split_width}')
	if false {
		exit(1)
	}
	return nr_splits
}

fn (ved &Ved) get_splits_from_to() (int, int) {
	from := ved.workspace_idx * ved.nr_splits
	to := from + ved.nr_splits
	return from, to
}

fn (mut ved Ved) update_cur_fn_name() {
	if !(ved.view.path.ends_with('.v') || ved.view.path.ends_with('.go')) {
		ved.cur_fn_name = ''
		return
	}
	if ved.view.lines.len < 2 {
		// Maybe the file is not loaded correctly (can happen on ved's launch)
		// Try to re-open it
		return
	}
	// TODO optimize, no allocations
	for i := int_min(ved.view.y - 1, ved.view.lines.len - 1); i >= 0; i-- {
		line := ved.view.lines[i]
		if line == '}' {
			ved.cur_fn_name = ''
			break
		}
		if line.starts_with('fn ') || line.starts_with('pub fn ') {
			ved.cur_fn_name = line.find_between('fn ', '{').trim_space()
			// Get just fn name, before "(" with params
			pos := ved.cur_fn_name.last_index('(') or { 0 }
			if pos > 0 {
				ved.cur_fn_name = ved.cur_fn_name[..pos]
			}
			break
		}
	}
}

fn read_grep_file_exts(workspaces []string) map[string][]string {
	mut res := map[string][]string{}
	for w in workspaces {
		path := '${w}/.ved'
		if !os.exists(path) {
			continue
		}
		f := os.read_file(path) or {
			println(err)
			continue
		}
		x := json.decode(Workspace, f) or {
			println(err)
			continue
		}
		res[w] = x.grep_file_extensions
		println('got ${x.grep_file_extensions} exts for workspace ${w}')
	}
	return res
}
