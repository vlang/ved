// Copyright (c) 2019-2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import strings
import gg

// View represents a single editor pane or "view", holding the state for an open file buffer.
// This includes the file path, content (lines), cursor position (x, y),
// scroll position (from), and other view-specific settings.
struct View {
mut:
	padding_left int
	from         int
	x            int
	y            int
	prev_x       int
	path         string
	short_path   string
	prev_path    string // for tt
	lines        []string
	page_height  int
	vstart       int
	vend         int // visual borders
	changed      bool
	error_y      int
	ved          &Ved = unsafe { nil }
	prev_y       int
	hash_comment bool
	hl_on        bool
	breakpoints  []int // line numbers with breakpoints
}

// new_view creates and initializes a new `View` instance.
fn (ved &Ved) new_view() View {
	res := View{
		padding_left: 0
		path:         ''
		from:         0
		y:            0
		x:            0
		prev_x:       0
		page_height:  ved.page_height
		vstart:       -1
		vend:         -1
		ved:          ved
		error_y:      -1
		prev_y:       -1
	}
	return res
}

// `mut res := word.clone()` ==>
// ['mut' 'res' 'word' 'clone']
// get_clean_words extracts a list of words from a line.
// A "word" is considered a contiguous sequence of alphanumeric characters and underscores.
fn get_clean_words(line string) []string {
	mut res := []string{}
	mut i := 0
	for i < line.len {
		// Skip bad first
		for i < line.len && !is_alpha_underscore(int(line[i])) {
			i++
		}
		// Read all good
		start2 := i
		for i < line.len && is_alpha_underscore(int(line[i])) {
			i++
		}
		// End of word, save it
		word := line[start2..i]
		res << word
		i++
	}
	return res
}

// open_file opens a file at the given `path`, loads its contents into the view's buffer,
// and optionally moves the cursor to `line_nr`. It also updates the editor's state,
// such as the list of open files and syntax highlighting settings.
fn (mut view View) open_file(path string, line_nr int) {
	println('open file "${path}"')
	if path == '' {
		return
	}
	// This path is in current workspace? Trim it. /code/v/file.v => file.v
	if path.starts_with(view.ved.workspace + '/') {
		view.short_path = path[view.ved.workspace.len..]
		if view.short_path.starts_with('/') {
			view.short_path = view.short_path[1..]
		}
	} else {
		// Optimize space, replace /Users/username with ~
		if path.starts_with(home_dir) {
			view.short_path = path.replace(home_dir, '~')
		} else {
			view.short_path = path
		}
	}
	mut ved := view.ved
	ved.set_current_syntax_idx(os.file_ext(path))
	// if os.exists(view.short_path) &&
	if view.short_path !in ['out', ''] && view.short_path !in ved.open_paths[ved.workspace_idx] {
		if ved.open_paths[ved.workspace_idx].len == 0 {
			ved.open_paths[ved.workspace_idx] = []string{cap: ved.nr_splits}
		}
		ved.open_paths[ved.workspace_idx] << view.short_path
	}
	if path != view.path {
		// Save cursor pos (Y)
		view.ved.file_y_pos[view.path] = view.y
		view.prev_path = view.path
	}
	/*
	mut lines := []string{}
	if rlines := os.read_lines(path) {
		lines = rlines
	}
	view.lines = lines
	*/
	view.lines = os.read_lines(path) or { []string{} }
	// get words map
	if view.lines.len < 1000 {
		println('getting words')
		// ticks := glfw.get_time()
		for line in view.lines {
			// words := line.split(' ')
			words := get_clean_words(line)
			for word in words {
				// clean_word := get_clean_word(word)
				// if clean_word == '' {
				// continue
				// }
				if word !in ved.words {
					ved.words << word
				}
			}
		}
		// took := glfw.get_time() - ticks
	}
	// Empty file, handle it
	if view.lines.len == 0 {
		view.lines << ''
	}
	view.path = path
	// view.short_path = path.replace(view.ved.workspace, '')
	// Calc padding_left
	nr_lines := view.lines.len
	s := '${nr_lines}'
	view.padding_left = s.len * ved.cfg.char_width + 8
	view.ved.save_session()
	// Go to old y for this file
	y := view.ved.file_y_pos[view.path]
	if y > 0 {
		view.set_y(y)
		if path != view.path {
			view.zz()
		}
	}
	// Call zz() if it's out of bounds
	if view.from > view.y || view.from + view.ved.page_height < view.y {
		// view.zz()
	}

	if line_nr != 0 {
		view.move_to_line(line_nr)
	}

	view.l()
	view.h() // so that cursor pos is correct and doesn't point to no longer existing text

	view.hash_comment = !view.path.ends_with('.v')
	view.hl_on = !view.path.ends_with('.md') && !view.path.ends_with('.txt')
		&& view.path.contains('.')
	view.changed = false
	view.ved.gg.refresh_ui()
	// go view.ved.write_changes_in_file_every_5s()
}

// reopen reloads the content of the file currently associated with the view from disk.
// This is useful for discarding changes or updating the view after external modifications.
fn (mut view View) reopen() {
	view.open_file(view.path, 0)
	view.changed = false
}

// save_file saves the current content of the view's buffer to its associated file on disk.
// It then triggers an asynchronous file formatting process.
fn (mut view View) save_file() {
	if view.path == '' {
		return
	}
	path := view.path
	view.ved.file_y_pos[view.path] = view.y
	println('saving file "${path}"')
	println('lines.len=${view.lines.len}')
	// line0 := view.lines[0]
	// println('line[0].len=$line0.len')
	mut file := os.create(path) or { panic('fail') }
	for line in view.lines {
		file.writeln(line.trim_right(' \t')) or { panic(err) }
	}
	file.close()
	spawn view.format_file()
	// If another split has the same file open, update it
	for mut v in view.ved.views {
		if v.path == view.path {
			v.reopen()
		}
	}
}

// format_file asynchronously runs an external formatting command (like `v fmt`, `goimports`, `prettier`)
// on the view's file. After formatting, it reloads the file to reflect the changes.
fn (mut view View) format_file() {
	view.ved.load_config2()
	if view.ved.cfg.disable_fmt {
		return
	}
	path := view.path
	// Run formatters
	fmt_cmd := view.ved.syntaxes[view.ved.current_syntax_idx].fmt_cmd.replace('<PATH>',
		os.quoted_path(path))
	if path.ends_with('.go') {
		println('running goimports')
		os.system('goimports -w "${path}"')
	} else if path.ends_with('.scss') {
		css := path.replace('.scss', '.css')
		os.system('sassc "${path}" > "${css}"')
	} else if path.ends_with('.js') {
		os.system('prettier --use-tabs -w "${path}"')
	} else if fmt_cmd != '' {
		os.system(fmt_cmd)
	}
	view.reopen()
	// update git diff
	view.ved.get_git_diff()
	view.changed = false
	// println('end of save file()')
	// println('_lines.len=$view.lines.len')
	// line0_ := view.lines[0]
	// println('_line[0].len=$line0_.len')
}

// line returns the content of the current line (at cursor position `y`) as a string.
fn (view &View) line() string {
	if view.y < 0 || view.y >= view.lines.len {
		return ''
	}
	return view.lines[view.y]
}

// uline returns the content of the current line as a slice of runes, suitable for multi-byte character manipulation.
fn (view &View) uline() []rune {
	return view.line().runes()
}

// char returns the character (as an integer rune) at the current cursor position (`x`).
fn (view &View) char() int {
	line := view.line()
	if line.len > 0 && view.x < line.len {
		return int(line[view.x])
	}
	return 0
}

// set_line replaces the content of the current line with `newline`.
fn (mut view View) set_line(newline string) {
	if view.y < 0 { // Basic sanity check
		return
	}
	if view.y < view.lines.len { // Check if index is within current bounds
		view.lines[view.y] = newline
	} else if view.y == view.lines.len { // Check if index is exactly one past the end
		view.lines << newline
	} else { // Index is too large
		// Optionally, append anyway or just return to prevent further issues
		view.lines << newline // Append as a fallback? Or just return? Append seems safer for paste.
	}
	view.changed = true
}

// set_y sets the vertical position (line number) of the cursor.
fn (mut view View) set_y(new_y int) {
	view.y = new_y
	view.ved.update_cur_fn_name()
}

// j moves the cursor down one line, handling scrolling and maintaining horizontal position. (Vim: `j`)
fn (mut view View) j() {
	if view.lines.len == 0 {
		return
	}
	line0 := view.line()
	view.set_y(view.y + 1)
	// Reached end
	if view.y >= view.lines.len {
		view.set_y(view.lines.len - 1)
		return
	}
	// Scroll
	if view.y >= view.from + view.page_height {
		view.from++
	}
	// Correct x if there are tabs on the next line
	_, nr_tabs1 := nr_spaces_and_tabs_in_line(line0)
	line := view.line()
	_, nr_tabs2 := nr_spaces_and_tabs_in_line(line)
	// println('tabs1,2=${nr_tabs1},${nr_tabs2}')
	// println(view.ved.cfg.tab_size)
	if nr_tabs2 > nr_tabs1 {
		view.x -= (nr_tabs2 - nr_tabs1) * view.ved.cfg.tab_size - 1
		if view.x < 0 {
			view.x = 0
		}
	}
	// Line below is shorter, move to the end of it
	if view.x > line.len - 1 {
		view.prev_x = view.x
		view.x = line.len - 1
		if view.x < 0 {
			view.x = 0
		}
	}
}

// k moves the cursor up one line, handling scrolling and maintaining horizontal position. (Vim: `k`)
fn (mut view View) k() {
	if view.y >= view.lines.len {
		view.y = view.lines.len - 1
	}
	if view.y <= 0 {
		return
	}
	line0 := view.line()
	view.set_y(view.y - 1)
	// Scroll
	if view.y < view.from && view.y >= 0 {
		view.from--
	}
	// Correct x if there are tabs on the prev line
	_, nr_tabs1 := nr_spaces_and_tabs_in_line(line0)
	line := view.line()
	_, nr_tabs2 := nr_spaces_and_tabs_in_line(line)
	// println('tabs1,2=${nr_tabs1},${nr_tabs2}')
	// println(view.ved.cfg.tab_size)
	if nr_tabs2 < nr_tabs1 {
		view.x -= (nr_tabs1 - nr_tabs2) * view.ved.cfg.tab_size - 1
		if view.x < 0 {
			view.x = 0
		}
	}
	// Line above is shorter, move to the end of it
	if view.x > line.len - 1 {
		view.prev_x = view.x
		view.x = line.len - 1
		if view.x < 0 {
			view.x = 0
		}
	}
}

// shift_h moves the cursor to the first visible line on the screen (the top of the current page). (Vim: `H`)
fn (mut view View) shift_h() {
	view.set_y(view.from)
}

// move_to_page_bot moves the cursor to the last visible line on the screen (the bottom of the current page). (Vim: `L`)
fn (mut view View) move_to_page_bot() {
	view.set_y(view.from + view.page_height - 1)
}

// l moves the cursor one character to the right. (Vim: `l`)
fn (mut view View) l() {
	line := view.line()
	if view.x < line.len {
		view.x++
	}
}

// h moves the cursor one character to the left. (Vim: `h`)
fn (mut view View) h() {
	if view.x > 0 {
		view.x--
	}
	line := view.line()
	// Cursor is outside the line, move it to the end of it
	if view.x > line.len {
		view.x = line.len
	}
}

// shift_g moves the cursor to the last line of the file. (Vim: `G`)
fn (mut view View) shift_g() {
	view.set_y(view.lines.len - 1)
	view.from = view.y - view.page_height + 1
	if view.from < 0 {
		view.from = 0
	}
}

// shift_a appends a space at the end of the current line. (Similar to Vim: `A`)
fn (mut view View) shift_a() {
	line := view.line()
	view.set_line('${line} ')
	view.x = view.uline().len - 1
}

// shift_i moves the cursor to the first non-whitespace character of the current line. (Vim: `^` or `I`)
fn (mut view View) shift_i() {
	view.x = 0
	for view.char() == view.ved.cfg.tab {
		view.x++
	}
}

// gg moves the cursor to the first line of the file. (Vim: `gg`)
fn (mut view View) gg() {
	view.from = 0
	view.set_y(0)
}

// shift_f scrolls the view down by one page. (Vim: `Ctrl+F`)
fn (mut view View) shift_f() {
	view.from += view.page_height
	if view.from >= view.lines.len {
		view.from = view.lines.len - 1
	}
	view.set_y(view.from)
}

// shift_b scrolls the view up by one page. (Vim: `Ctrl+B`)
fn (mut view View) shift_b() {
	view.from -= view.page_height
	if view.from < 0 {
		view.from = 0
	}
	view.set_y(view.from)
}

// dd deletes the current line and copies it to the yank buffer. (Vim: `dd`)
fn (mut view View) dd() {
	if view.lines.len == 0 {
		return
	}
	mut ved := view.ved
	ved.prev_key = gg.KeyCode.invalid
	ved.prev_cmd = 'dd'
	ved.ylines = []
	ved.ylines << view.line()
	view.lines.delete(view.y)
	if view.y == view.lines.len {
		view.k()
	}
	view.changed = true
}

// shift_right indents the current line or the visually selected lines by one level. (Vim: `>`)
fn (mut view View) shift_right() {
	// No selection, shift current line
	if view.vstart == -1 {
		view.set_line('\t${view.line()}')
		return
	}
	for i := view.vstart; i <= view.vend; i++ {
		line := view.lines[i]
		view.lines[i] = '\t${line}'
	}
}

// shift_left un-indents the current line or the visually selected lines by one level. (Vim: `<`)
fn (mut view View) shift_left() {
	if view.vstart == -1 {
		line := view.line()
		if !line.starts_with('\t') {
			return
		}
		view.set_line(line[1..])
		return
	}
	for i := view.vstart; i <= view.vend; i++ {
		line := view.lines[i]
		if !line.starts_with('\t') {
			continue
		}
		view.lines[i] = line[1..]
	}
}

// delete_char deletes the character currently under the cursor. (Vim: `x`)
fn (mut v View) delete_char() {
	u := v.uline()
	if u.len < 1 || v.x >= u.len {
		return
	}
	mut new_line := unsafe { u[..v.x] }
	right := u[v.x + 1..]
	new_line << right
	v.set_line(new_line.string())
	if v.x >= new_line.len {
		v.x = new_line.len - 1
	}
}

// shift_c deletes from the cursor to the end of the line and returns the deleted text. (Similar to Vim: `C`)
fn (mut view View) shift_c() string {
	line := view.line()
	s := line[..view.x]
	deleted := line[view.x..]
	view.set_line('${s} ')
	view.x = s.len
	return deleted
}

// insert_text inserts the given string `s` at the current cursor position.
fn (mut view View) insert_text(s string) {
	line := view.line()
	if line.len == 0 {
		view.set_line('${s} ')
	} else {
		if view.x > line.len {
			view.x = line.len
		}
		uline := line.runes()
		if view.x > uline.len {
			return
		}
		left := uline[..view.x].string()
		right := uline[view.x..uline.len].string()
		// Insert char in the middle
		res := '${left}${s}${right}'
		view.set_line(res)
	}
	view.x += s.runes().len
	view.changed = true
	// Show autocomplete window on `.`
	if s == '.' {
		println('DOOOT, SHOW WINDOW')
		view.ved.mode = .autocomplete
		view.ved.refresh = true
		view.ved.gg.refresh_ui()
		go view.ved.get_line_info()
	}
}

// backspace handles a backspace key press, deleting the character before the cursor or joining lines if at the beginning of a line.
fn (mut view View) backspace() {
	if view.x == 0 {
		if view.ved.cfg.backspace_go_up && view.y > 0 {
			view.x = 0
			view.y--
			view.x = view.lines[view.y].len
			view.lines.delete(view.y + 1)
			view.changed = true
		}
		return
	}
	// line := view.line()
	uline := view.uline()
	// println('line="$line" uline="$uline.string()"')
	left := uline[..view.x - 1].string()
	mut right := ''
	if view.x < uline.len {
		right = uline[view.x..].string()
	}
	view.set_line('${left}${right}')
	view.x--
	if view.ved.prev_insert.len > 0 {
		view.ved.prev_insert = view.ved.prev_insert[..view.ved.prev_insert.len - 1] // TODO runes
	}
}

// yy yanks (copies) the current line into the yank buffer. (Vim: `yy`)
fn (mut view View) yy() {
	view.ved.ylines = [view.line()]
}

// p pastes the content of the yank buffer on new lines below the current cursor position. (Vim: `p`)
fn (mut view View) p() {
	for line in view.ved.ylines {
		view.o()
		view.set_line(line)
	}
}

// shift_o opens a new, indented line above the current line. (Vim: `O`)
fn (mut view View) shift_o() {
	view.o_generic(0)
}

// o opens a new, indented line below the current line. (Vim: `o`)
fn (mut view View) o() {
	view.o_generic(1)
}

fn (mut view View) o_generic(delta int) {
	view.y += delta
	// Insert the same amount of spaces/tabs as in prev line
	prev_line := if view.lines.len == 0 || view.y == 0 {
		''
	} else {
		// Ensure index is valid before accessing
		prev_idx := view.y - 1
		if prev_idx >= 0 && prev_idx < view.lines.len { // Added check
			view.lines[prev_idx]
		} else {
			// This case shouldn't happen based on the logic, but handle defensively
			'' // Default to no indentation if index is bad
		}
	}
	nr_spaces, nr_tabs := nr_spaces_and_tabs_in_line(prev_line)
	mut new_line := strings.repeat(`\t`, nr_tabs) + strings.repeat(` `, nr_spaces)
	if prev_line.ends_with('{') || prev_line.ends_with('{ ') {
		new_line += '\t '
	} else if !new_line.ends_with(' ') {
		new_line += ' '
	}
	view.x = new_line.len - 1
	if view.y >= view.lines.len {
		view.lines << new_line
	} else {
		view.lines.insert(view.y, new_line)
	}
	view.changed = true
}

// enter handles an enter key press in insert mode, splitting the current line at the cursor position.
fn (mut view View) enter() {
	// Create new line
	// And move everything to the right of the cursor to it
	pos := view.x
	line := view.line()
	if pos >= line.len - 1 && line != '' && line != ' ' {
		// {} insertion
		if line.ends_with('{ ') {
			view.o()
			view.x--
			view.insert_text('}')
			view.y--
			view.o()
			// view.insert_text('\t')
			// view.x = 0
		} else {
			view.o()
		}
		return
	}
	// if line == '' {
	// view.o()
	// return
	// }
	uline := line.runes()
	mut right := ''
	if pos < uline.len {
		right = uline[pos..].string()
	}
	left := uline[..pos].string()
	view.set_line(left)
	view.o()
	view.set_line(right)
	view.x = 0
}

// join joins the current line with the line below it. (Vim: `J`)
fn (mut view View) join() {
	if view.y == view.lines.len - 1 {
		return
	}
	// Add next line to current line
	line := view.line()
	second_line := view.lines[view.y + 1]
	joined := line + second_line
	view.set_line(joined)
	view.y++
	view.dd()
	view.y--
	// view.prev_cmd = "J"
}

// y_visual yanks (copies) the visually selected lines into the yank buffer.
fn (mut v View) y_visual() {
	mut ylines := []string{}
	vtop, vbot := if v.vstart < v.vend { v.vstart, v.vend } else { v.vend, v.vstart }
	for i := vtop; i <= vbot; i++ {
		ylines << v.lines[i]
	}
	mut ved := v.ved
	ved.ylines = ylines
	// Copy YY to clipboard if +(=) was pressed before
	if ved.prev_key == .equal {
		ved.cb.copy(ylines.join('\n'))
	}
	v.vstart = -1
	v.vend = -1
}

// d_visual deletes the visually selected lines and copies them to the yank buffer.
fn (mut view View) d_visual() {
	vtop := if view.vstart < view.vend { view.vstart } else { view.vend }
	view.y_visual()
	for i := 0; i < view.ved.ylines.len; i++ {
		view.lines.delete(vtop)
	}
	// Move cursor to a valid position using k
	if view.y >= view.lines.len {
		view.y = view.lines.len
	} else {
		view.y += 1
	}
	view.k()
}

// cw changes the word under the cursor: deletes it and enters insert mode. (Vim: `cw`)
fn (mut view View) cw() {
	mut ved := view.ved
	ved.prev_insert = ''
	view.dw(false)
	ved.prev_cmd = 'cw'
	// view.ved.set_insert() // don't call this since it resets prev_insert
	ved.mode = .insert
	ved.just_switched = true
}

// returns the removed word
// dw deletes the word under the cursor. If `del_whitespace` is true, trailing whitespace is also deleted. (Vim: `dw`)
fn (mut view View) dw(del_whitespace bool) { // string {
	mut ved := view.ved
	typ := is_alpha(u8(view.char()))
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x < 0 || view.x >= line.len - 1 {
			break
		}
		if typ == is_alpha(u8(view.char())) {
			// println('del x=$view.x len=$line.len')
			view.delete_char()
		} else {
			break
		}
	}
	// Delete whitespace after the deleted word
	if del_whitespace {
		for is_whitespace(u8(view.char())) {
			line := view.line()
			if view.x < 0 || view.x >= line.len {
				break
			}
			view.delete_char()
		}
	}
	ved.prev_cmd = 'dw'
}

// returns the removed word
// db deletes the word backwards from the cursor position. (Vim: `db`)
fn (mut view View) db(del_whitespace bool) { // string {
	mut ved := view.ved
	typ := is_alpha(u8(view.char()))
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x < 0 || view.x >= line.len - 1 {
			break
		}
		view.x--
		if typ == is_alpha_underscore(u8(view.char())) {
			// println('del x=$view.x len=$line.len')
			view.delete_char()
		} else {
			break
		}
	}
	view.x++
	// Delete whitespace after the deleted word
	/*
	if del_whitespace {
		for is_whitespace(u8(view.char())) {
			line := view.line()
			if view.x < 0 || view.x >= line.len {
				break
			}
			view.delete_char()
		}
	}
	*/
	ved.prev_cmd = 'db'
}

// TODO COPY PASTA
// same as cw but deletes underscores
// ce changes the word/token under the cursor. Similar to `cw` but may use a different definition of a "word".
fn (mut view View) ce() {
	mut ved := view.ved
	view.de()
	ved.prev_cmd = 'ce'
	view.ved.set_insert()
}

// w moves the cursor forward to the beginning of the next word. (Vim: `w`)
fn (mut view View) w() {
	line := view.line()
	typ := is_alpha_underscore(view.char())
	// Go to end of current word
	for view.x < line.len - 1 && typ == is_alpha_underscore(view.char()) {
		view.x++
	}
	// Go to start of next word
	for view.x < line.len - 1 && view.char() == 32 {
		view.x++
	}
}

// b moves the cursor backward to the beginning of the previous word. (Vim: `b`)
fn (mut view View) b() {
	// line := view.line()
	// Go to start of prev word
	for view.x > 0 && view.char() == 32 {
		view.x--
	}
	typ := is_alpha_underscore(view.char())
	// Go to start of current word
	for view.x > 0 && typ == is_alpha_underscore(view.char()) {
		view.x--
	}
}

// de deletes from the cursor to the end of the current word/token. (Vim: `de`)
fn (mut view View) de() {
	mut ved := view.ved
	typ := is_alpha_underscore(view.char())
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x >= 0 && view.x < line.len && typ == is_alpha_underscore(view.char()) {
			view.delete_char()
		} else {
			break
		}
	}
	ved.prev_cmd = 'de'
}

// delete all characters before and after the cursor inside '', "", () etc
// ci "Change inside". Deletes the text within a surrounding delimiter (like quotes or parentheses)
// based on the `key` pressed, and enters insert mode. (Vim: `ci'`)
fn (mut view View) ci(key gg.KeyCode) {
	mut ved := view.ved
	line := view.line()
	defer {
		ved.prev_cmd = ''
	}
	match key {
		.apostrophe {
			if !line.contains("'") {
				return
			}
			mut start := view.x
			for line[start] != `'` {
				start--
			}
			mut end := view.x
			for line[end] != `'` {
				end++
			}
			view.set_line(line[..start + 1] + line[end..])
			view.x = start + 1
			view.ved.set_insert()
		}
		._9 {}
		else {}
	}
	// match
	// view.dw()
}

// zz centers the current line vertically on the screen. (Vim: `zz`)
fn (mut view View) zz() {
	view.from = view.y - view.ved.page_height / 2
	if view.from < 0 {
		view.from = 0
	}
}

// r replaces the single character under the cursor with the character(s) in `s`. (Vim: `r`)
fn (mut view View) r(s string) {
	view.delete_char()
	view.insert_text(s)
	view.x--
}

// tt toggles to the previously active view/file.
fn (mut view View) tt() {
	if view.prev_path == '' {
		return
	}
	mut ved := view.ved
	ved.prev_key = .invalid
	view.open_file(view.prev_path, 0)
}

// move_to_line jumps the cursor and view to a specific `line` number.
fn (mut view View) move_to_line(line int) {
	view.prev_y = view.y
	view.from = line
	view.set_y(line)
	view.zz()
}

// ctrl+a - increase number by one
// super_a finds the first number on the current line and increases it by `diff`. (Vim: `Ctrl+A` for +1)
fn (mut view View) super_a(diff int) {
	line := view.line()
	mut num_start_pos := -1
	for i, r in line {
		if r >= `0` && r <= `9` {
			num_start_pos = i
			break
		}
	}
	if num_start_pos == -1 {
		return
	}
	s := line[num_start_pos..]
	vals := s.fields()
	number := vals[0].int()
	new_line := line.replace_once(number.str(), (number + diff).str())
	view.set_line(new_line)
}

// is_alpha checks if a byte represents an alphanumeric character (`a-z`, `A-Z`, `0-9`).
fn is_alpha(r u8) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`)
}

// is_whitespace checks if a byte represents a whitespace character (space or tab).
fn is_whitespace(r u8) bool {
	return r == ` ` || r == `\t`
}

// is_alpha_underscore checks if an integer (rune) represents an alphanumeric character, an underscore, a hash, or a dollar sign.
fn is_alpha_underscore(r int) bool {
	return is_alpha(u8(r)) || u8(r) == `_` || u8(r) == `#` || u8(r) == `$`
}

// break_text splits a single string `s` into an array of strings, ensuring no line exceeds `max` characters.
fn break_text(s string, max int) []string {
	mut lines := []string{}
	mut start := 0
	for i := 0; i < s.len; i++ {
		if i == s.len - 1 {
			// Include the very last char
			lines << s[start..i + 1]
			break
		}
		if i - start >= max {
			lines << s[start..i]
			start = i
		}
	}
	return lines
}
