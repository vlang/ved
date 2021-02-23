// Copyright (c) 2019-2021 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import strings
import gg

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
	ved          &Ved
	prev_y       int
	hash_comment bool
	hl_on        bool
}

fn (ved &Ved) new_view() View {
	res := View{
		padding_left: 0
		path: ''
		from: 0
		y: 0
		x: 0
		prev_x: 0
		page_height: ved.page_height
		vstart: -1
		vend: -1
		ved: ved
		error_y: -1
		prev_y: -1
	}
	return res
}

// `mut res := word.clone()` ==>
// ['mut' 'res' 'word' 'clone']
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

fn (mut view View) open_file(path string) {
	println('open file "$path"')
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
		view.short_path = path
	}
	mut ved := view.ved
	// if os.exists(view.short_path) &&
	if view.short_path !in ['out', ''] && view.short_path !in ved.open_paths[ved.workspace_idx] {
		if ved.open_paths[ved.workspace_idx].len == 0 {
			ved.open_paths[ved.workspace_idx] = []string{cap: ved.nr_splits}
		}
		ved.open_paths[ved.workspace_idx] << view.short_path
	}
	mut is_new := false
	if path != view.path {
		is_new = true
		// Save cursor pos (Y)
		// view.ved.file_y_pos.set(view.path, view.y)
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
				if !(word in ved.words) {
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
	s := '$nr_lines'
	view.padding_left = s.len * ved.char_width + 8
	view.ved.save_session()
	// Go to old y
	if is_new {
		tmp := view.y
		if view.prev_y > -1 {
			view.y = view.prev_y
			view.zz()
		}
		view.prev_y = tmp
	}
	if false {
		y := view.ved.file_y_pos[view.path]
		if y > 0 {
			view.y = y
		}
	}
	view.hash_comment = !view.path.ends_with('.v')
	view.hl_on = !view.path.ends_with('.md') && !view.path.ends_with('.txt')
	view.changed = false
	view.ved.gg.refresh_ui()
}

fn (mut view View) reopen() {
	view.open_file(view.path)
	view.changed = false
}

fn (mut view View) save_file() {
	view.x = view.x // TODO remove once the mut bug is fixed
	if view.path == '' {
		return
	}
	path := view.path
	println('saving file "$path"')
	println('lines.len=$view.lines.len')
	// line0 := view.lines[0]
	// println('line[0].len=$line0.len')
	mut file := os.create(path) or { panic('fail') }
	for line in view.lines {
		file.writeln(line.trim_right(' \t')) or { panic(err) }
	}
	file.close()
	go view.format_file()
	// If another split has the same file open, update it
	for mut v in view.ved.views {
		if v.path == view.path {
			v.reopen()
		}
	}
}

fn (mut view View) format_file() {
	path := view.path
	// Run formatters
	if path.ends_with('.go') {
		println('running goimports')
		os.system('goimports -w "$path"')
	} else if path.ends_with('.scss') {
		css := path.replace('.scss', '.css')
		os.system('sassc "$path" > "$css"')
	} else if path.ends_with('.v') {
		os.system('v fmt -w $path')
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

fn (view &View) line() string {
	if view.y < 0 || view.y >= view.lines.len {
		return ''
	}
	return view.lines[view.y]
}

fn (view &View) uline() ustring {
	return view.line().ustring()
}

fn (view &View) char() int {
	line := view.line()
	if line.len > 0 {
		return int(line[view.x])
	}
	return 0
}

fn (mut view View) set_line(newline string) {
	if view.y + 1 > view.lines.len {
		view.lines << newline
	} else {
		view.lines[view.y] = newline
	}
	view.changed = true
}

fn (mut view View) j() {
	if view.lines.len == 0 {
		return
	}
	view.y++
	// Reached end
	if view.y >= view.lines.len {
		view.y = view.lines.len - 1
		return
	}
	// Scroll
	if view.y >= view.from + view.page_height {
		view.from++
	}
	// Line below is shorter, move to the end of it
	line := view.line()
	if view.x > line.len - 1 {
		view.prev_x = view.x
		view.x = line.len - 1
		if view.x < 0 {
			view.x = 0
		}
	}
}

fn (mut view View) k() {
	if view.y <= 0 {
		return
	}
	view.y--
	if view.y < view.from && view.y > 0 {
		view.from--
	}
	// Line above is shorter, move to the end of it
	line := view.line()
	if view.x > line.len - 1 {
		view.prev_x = view.x
		view.x = line.len - 1
		if view.x < 0 {
			view.x = 0
		}
	}
}

fn (mut view View) shift_h() {
	view.y = view.from
}

fn (mut view View) move_to_page_bot() {
	view.y = view.from + view.page_height - 1
}

fn (mut view View) l() {
	line := view.line()
	if view.x < line.len - 1 {
		view.x++
	}
}

fn (mut view View) shift_g() {
	view.y = view.lines.len - 1
	view.from = view.y - view.page_height + 1
	if view.from < 0 {
		view.from = 0
	}
}

fn (mut view View) shift_a() {
	line := view.line()
	view.set_line('$line ')
	view.x = view.uline().len - 1
}

fn (mut view View) shift_i() {
	view.x = 0
	for view.char() == view.ved.cfg.tab {
		view.x++
	}
}

fn (mut view View) gg() {
	view.from = 0
	view.y = 0
}

fn (mut view View) shift_f() {
	view.from += view.page_height
	if view.from >= view.lines.len {
		view.from = view.lines.len - 1
	}
	view.y = view.from
}

fn (mut view View) shift_b() {
	view.from -= view.page_height
	if view.from < 0 {
		view.from = 0
	}
	view.y = view.from
}

fn (mut view View) dd() {
	if view.lines.len != 0 {
		mut ved := view.ved
		ved.prev_key = gg.KeyCode(-1)
		ved.prev_cmd = 'dd'
		ved.ylines = []
		ved.ylines << view.line()
		view.lines.delete(view.y)
		view.changed = true
	}
}

fn (mut view View) shift_right() {
	// No selection, shift current line
	if view.vstart == -1 {
		view.set_line('\t$view.line()')
		return
	}
	for i := view.vstart; i <= view.vend; i++ {
		line := view.lines[i]
		view.lines[i] = '\t$line'
	}
}

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

fn (mut v View) delete_char() {
	u := v.uline()
	if u.len < 1 || v.x >= u.len {
		return
	}
	left := u.left(v.x)
	right := u.right(v.x + 1)
	new_line := left + right
	v.set_line(new_line)
	if v.x >= new_line.len {
		v.x = new_line.len - 1
	}
}

fn (mut view View) shift_c() string {
	line := view.line()
	s := line[..view.x]
	deleted := line[view.x..]
	view.set_line('$s ')
	view.x = s.len
	return deleted
}

fn (mut view View) insert_text(s string) {
	line := view.line()
	if line.len == 0 {
		view.set_line('$s ')
	} else {
		if view.x >= line.len {
			view.x = line.len
		}
		uline := line.ustring()
		if view.x >= uline.len {
			return
		}
		left := uline.substr(0, view.x)
		right := uline.substr(view.x, uline.len)
		// Insert chat in the middle
		res := '$left$s$right'
		view.set_line(res)
	}
	view.x += s.ustring().len
	view.changed = true
}

fn (mut view View) backspace(go_up bool) {
	if view.x == 0 {
		if go_up && view.y > 0 {
			view.x = 0
			view.y--
			view.x = view.lines[view.y].len
			view.lines.delete(view.y + 1)
			view.changed = true
		}
		return
	}
	line := view.line()
	uline := view.uline()
	println('line="$line" uline="$uline"')
	left := uline.left(view.x - 1)
	mut right := ''
	if view.x < uline.len {
		right = uline.right(view.x)
	}
	view.set_line('$left$right')
	view.x--
}

fn (mut view View) yy() {
	view.ved.ylines = [view.line()]
}

fn (mut view View) p() {
	for line in view.ved.ylines {
		view.o()
		view.set_line(line)
	}
}

fn (mut view View) shift_o() {
	view.o_generic(0)
}

fn (mut view View) o() {
	view.o_generic(1)
}

fn (mut view View) o_generic(delta int) {
	view.y += delta
	// Insert the same amount of spaces/tabs as in prev line
	prev_line := if view.lines.len == 0 || view.y == 0 { '' } else { view.lines[view.y - 1] }
	mut nr_spaces := 0
	mut nr_tabs := 0
	mut i := 0
	for i < prev_line.len && (prev_line[i] == ` ` || prev_line[i] == `\t`) {
		if prev_line[i] == ` ` {
			nr_spaces++
		}
		if prev_line[i] == `\t` {
			nr_tabs++
		}
		i++
	}
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
	uline := line.ustring()
	mut right := ''
	if pos < uline.len {
		right = uline.right(pos)
	}
	left := uline.left(pos)
	view.set_line(left)
	view.o()
	view.set_line(right)
	view.x = 0
}

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

fn (mut v View) y_visual() {
	mut ylines := []string{}
	for i := v.vstart; i <= v.vend; i++ {
		ylines << v.lines[i]
	}
	mut ved := v.ved
	ved.ylines = ylines
	// Copy YY to clipboard TODO
	// mainWindow.SetClipboardString(strings.Join(ylines, "\n"))
	v.vstart = -1
	v.vend = -1
}

fn (mut view View) d_visual() {
	view.y_visual()
	for i := 0; i < view.ved.ylines.len; i++ {
		view.lines.delete(view.y)
	}
}

fn (mut view View) cw() {
	mut ved := view.ved
	view.dw(false)
	ved.prev_cmd = 'cw'
	// view.ved.set_insert() // don't call this since it resets prev_insert
	ved.mode = .insert
	ved.just_switched = true
}

// returns the removed word
fn (mut view View) dw(del_whitespace bool) { // string {
	mut ved := view.ved
	typ := is_alpha(byte(view.char()))
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x < 0 || view.x >= line.len - 1 {
			break
		}
		if typ == is_alpha(byte(view.char())) {
			// println('del x=$view.x len=$line.len')
			view.delete_char()
		} else {
			break
		}
	}
	// Delete whitespace after the deleted word
	if del_whitespace {
		for is_whitespace(byte(view.char())) {
			line := view.line()
			if view.x < 0 || view.x >= line.len {
				break
			}
			view.delete_char()
		}
	}
	ved.prev_cmd = 'dw'
}

// TODO COPY PASTA
// same as cw but deletes underscores
fn (mut view View) ce() {
	mut ved := view.ved
	view.de()
	ved.prev_cmd = 'ce'
	view.ved.set_insert()
}

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
			for line[start] != `\'` {
				start--
			}
			mut end := view.x
			for line[end] != `\'` {
				end++
			}
			view.set_line(line[..start + 1] + line[end..])
			view.x = start + 1
			view.ved.set_insert()
		}
		else {}
	}
	// view.dw()
}

fn (mut view View) zz() {
	view.from = view.y - view.ved.page_height / 2
	if view.from < 0 {
		view.from = 0
	}
}

fn (mut view View) r(s string) {
	view.delete_char()
	view.insert_text(s)
	view.x--
}

fn (mut view View) tt() {
	if view.prev_path == '' {
		return
	}
	mut ved := view.ved
	ved.prev_key = gg.KeyCode(-1)
	view.open_file(view.prev_path)
}

fn (mut view View) move_to_line(line int) {
	view.prev_y = view.y
	view.from = line
	view.y = line
	view.zz()
}

// Fit lines  into 80 chars
fn (mut view View) gq() {
	mut ved := view.ved
	if ved.mode != .visual {
		return
	}
	view.y_visual()
	max := ved.max_chars(0)
	// Join all selected lines into a single string
	joined := ved.ylines.join('\n')
	// Delete what we selected
	for yline in ved.ylines {
		if yline == '' {
			continue
		}
		view.lines.delete(view.y)
	}
	new_lines := break_text(joined, max - 1)
	for line in new_lines {
		view.insert_text(line)
		view.o()
	}
	ved.mode = .normal
}

fn is_alpha(r byte) bool {
	return ((r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`))
}

fn is_whitespace(r byte) bool {
	return r == ` ` || r == `\t`
}

fn is_alpha_underscore(r int) bool {
	return (is_alpha(byte(r)) || byte(r) == `_` || byte(r) == `#` || byte(r) == `$`)
}

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
