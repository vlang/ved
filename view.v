// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main

import (
	os
	strings
)

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
	vid          &Vid
	prev_y       int
	hash_comment bool
	hl_on        bool
}

fn (vid &Vid) new_view() View {
	res := View {
		padding_left: 0
		path: ''
		from: 0
		y: 0
		x: 0
		prev_x: 0
		page_height: vid.page_height
		vstart: -1
		vend: -1
		vid: vid
		error_y: -1
		prev_y: -1
	}
	return res
}

// `mut res := word.clone()` ==>
// ['mut' 'res' 'word' 'clone']
fn get_clean_words(line string) []string {
	mut res := []string
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

fn (view mut View) open_file(path string) {
	println('open file "$path"')
	if path == '' {
		return
	}
	mut vid := view.vid
	mut is_new := false
	if path != view.path {
		is_new = true
		// Save cursor pos (Y)
		// view.vid.file_y_pos.set(view.path, view.y)
		view.prev_path = view.path
	}

	mut lines := []string
	if rlines := os.read_lines(path) { lines = rlines }

	view.lines = lines
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
				if !(word in vid.words) {
					vid.words << word
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
	view.short_path = path.replace(view.vid.workspace, '')
	if view.short_path.starts_with('/') {
		view.short_path = view.short_path[1..]
	}
	// Calc padding_left
	nr_lines := view.lines.len
	s := '$nr_lines'
	view.padding_left = s.len * vid.char_width + 8
	view.vid.save_session()
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
		y := view.vid.file_y_pos[view.path]
		if y > 0 {
			view.y = y
		}
	}
	view.hash_comment = !view.path.ends_with('.v')
	view.hl_on = !view.path.ends_with('.md')
	view.changed = false
}

fn (view mut View) reopen() {
	view.open_file(view.path)
	view.changed = false
}

fn (view mut View) save_file() {
	view.x = view.x // TODO remove once the mut bug is fixed
	if view.path == '' {
		return
	}
	path := view.path
	println('saving file "$path"')
	println('lines.len=$view.lines.len')
	//line0 := view.lines[0]
	//println('line[0].len=$line0.len')
	mut file := os.create(path) or {
		panic('fail')
	}
	for line in view.lines {
		file.writeln(line.trim_right(' \t'))
	}
	file.close()
	go view.format_file()
}

fn (view mut View) format_file() {
	path := view.path
	// Run formatters
	if path.ends_with('.go') {
		println('running goimports')
		os.system('goimports -w "$path"')
	}
	else if path.ends_with('.scss') {
		css := path.replace('.scss', '.css')
		os.system('sassc "$path" > "$css"')
	}
	else if path.ends_with('.v') && path.contains('vlib/v/') {
		os.system('v fmt -w $path')
	}
	view.reopen()
	// update git diff
	view.vid.get_git_diff()
	view.changed = false
	//println('end of save file()')
	//println('_lines.len=$view.lines.len')
	//line0_ := view.lines[0]
	//println('_line[0].len=$line0_.len')
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

fn (view mut View) set_line(newline string) {
	if view.y + 1 > view.lines.len {
		view.lines << newline
	}
	else {
		view.lines[view.y] = newline
	}
	view.changed = true
}

fn (view mut View) j() {
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

fn (view mut View) k() {
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

fn (view mut View) shift_h() {
	view.y = view.from
}

fn (view mut View) move_to_page_bot() {
	view.y = view.from + view.page_height - 1
}

fn (view mut View) l() {
	line := view.line()
	if view.x < line.len - 1 {
		view.x++
	}
}

fn (view mut View) shift_g() {
	view.y = view.lines.len - 1
	view.from = view.y - view.page_height + 1
	if view.from < 0 {
		view.from = 0
	}
}

fn (view mut View) shift_a() {
	line := view.line()
	view.set_line('$line ')
	view.x = view.uline().len - 1
}

fn (view mut View) shift_i() {
	view.x = 0
	for view.char() == view.vid.cfg.tab {
		view.x++
	}
}

fn (view mut View) gg() {
	view.from = 0
	view.y = 0
}

fn (view mut View) shift_f() {
	view.from += view.page_height
	if view.from >= view.lines.len {
		view.from = view.lines.len - 1
	}
	view.y = view.from
}

fn (view mut View) shift_b() {
	view.from -= view.page_height
	if view.from < 0 {
		view.from = 0
	}
	view.y = view.from
}

fn (view mut View) dd() {
	if view.lines.len != 0 {
		mut vid := view.vid
		vid.prev_key = -1
		vid.prev_cmd = 'dd'
		vid.ylines = []
		vid.ylines << view.line()
		view.lines.delete(view.y)
		view.changed = true
	}
}

fn (view mut View) shift_right() {
	// No selection, shift current line
	if view.vstart == -1 {
		view.set_line('\t${view.line()}')
		return
	}
	for i := view.vstart; i <= view.vend; i++ {
		line := view.lines[i]
		view.lines[i] = '\t$line'
	}
}

fn (view mut View) shift_left() {
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

fn (v mut View) delete_char() {
	u := v.uline()
	if v.x >= u.len {
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

fn (view mut View) shift_c() string {
	line := view.line()
	s := line[..view.x]
	deleted := line[view.x..]
	view.set_line('${s} ')
	view.x = s.len
	return deleted
}

fn (view mut View) insert_text(s string) {
	line := view.line()
	if line.len == 0 {
		view.set_line('$s ')
	}
	else {
		if view.x >= line.len {
			view.x = line.len
		}
		uline := line.ustring()
		if view.x >= uline.len {
			return
		}
		left := uline.substr(0,view.x)
		right := uline.substr(view.x,uline.len)
		// Insert chat in the middle
		res := '${left}${s}${right}'
		view.set_line(res)
	}
	view.x += s.ustring().len
	view.changed = true
}

fn (view mut View) backspace(go_up bool) {
	if view.x == 0 {
		if go_up && view.y > 0 {
			view.x = 0
			view.y--
			view.x = view.lines[view.y].len
			view.lines.delete(view.y+1)
			view.changed = true
		}
		return
	}
	uline := view.uline()
	left := uline.left(view.x - 1)
	mut right := ''
	if view.x < uline.len  {
		right = uline.right(view.x)
	}
	view.set_line('${left}${right}')
	view.x--
}

fn (view mut View) yy() {
	mut ylines := []string
	ylines << (view.line())
	view.vid.ylines = ylines
}

fn (view mut View) p() {
	for line in view.vid.ylines {
		view.o()
		view.set_line(line)
	}
}

fn (view mut View) shift_o() {
	view.o_generic(0)
}

fn (view mut View) o() {
	view.o_generic(1)
}

fn (view mut View) o_generic(delta int) {
	view.y += delta
	// Insert the same amount of spaces/tabs as in prev line
	prev_line := if view.lines.len == 0 || view.y == 0 {
		''
	} else {
		view.lines[view.y - 1]
	}
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


	view.x = new_line.len-1
	if view.y >= view.lines.len {
		view.lines << new_line
	}
	else {
		view.lines.insert(view.y, new_line)
	}
	view.changed = true
}

fn (view mut View) enter() {
	// Create new line
	// And move everything to the right of the cursor to it
	pos := view.x
	line := view.line()
	if pos >= line.len-1 && line != '' && line != ' ' {
		// {} insertion
		if line.ends_with('{ ') {
			view.o()
			view.x--
			view.insert_text('}')
			view.y--
			view.o()
			//view.insert_text('\t')
			//view.x = 0
		} else {
			view.o()
		}
		return
	}
	//if line == '' {
		//view.o()
		//return
	//}
	uline := line.ustring()
	mut right := ''
	if pos < uline.len{
		right = uline.right(pos)
	}
	left := uline.left(pos)
	view.set_line(left)
	view.o()
	view.set_line(right)
	view.x = 0
}

fn (view mut View) join() {
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

fn (v mut View) y_visual() {
	mut ylines := []string
	for i := v.vstart; i <= v.vend; i++ {
		ylines << v.lines[i]
	}
	mut vid := v.vid
	vid.ylines = ylines
	// Copy YY to clipboard TODO
	// mainWindow.SetClipboardString(strings.Join(ylines, "\n"))
	v.vstart = -1
	v.vend = -1
}

fn (view mut View) d_visual() {
	view.y_visual()
	for i := 0; i < view.vid.ylines.len; i++ {
		view.lines.delete(view.y)
	}
}

fn (view mut View) cw() {
	mut vid := view.vid
	view.dw()
	vid.prev_cmd = 'cw'
	view.vid.set_insert()
}

fn (view mut View) dw() {
	mut vid := view.vid
	typ := is_alpha(view.char())
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x <= 0 || view.x >= line.len - 1 {
			break
		}
		if typ == is_alpha(view.char()) {
			println('del x=$view.x len=$line.len')
			view.delete_char()
		}
		else {
			break
		}
	}
	// Delete whitespace after the deleted word
	for is_whitespace(view.char()) {
		line := view.line()
		if view.x <= 0 || view.x >= line.len {
			break
		}
		view.delete_char()
	}

	vid.prev_cmd = 'dw'
}

// TODO COPY PASTA
// same as cw but deletes underscores
fn (view mut View) ce() {
	mut vid := view.vid
	view.de()
	vid.prev_cmd = 'ce'
	view.vid.set_insert()
}

fn (view mut View) w() {
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

fn (view mut View) b() {
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

fn (view mut View) de() {
	mut vid := view.vid
	typ := is_alpha_underscore(view.char())
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x >= 0 && view.x < line.len && typ == is_alpha_underscore(view.char()) {
			view.delete_char()
		}
		else {
			break
		}
	}
	vid.prev_cmd = 'de'
}

fn (view mut View) zz() {
	view.from = view.y - view.vid.page_height / 2
	if view.from < 0 {
		view.from = 0
	}
}

fn (view mut View) r(s string) {
	view.delete_char()
	view.insert_text(s)
	view.x--
}

fn (view mut View) tt() {
	if view.prev_path == '' {
		return
	}
	mut vid := view.vid
	vid.prev_key = -1
	view.open_file(view.prev_path)
}

fn (view mut View) move_to_line(line int) {
	view.from = line
	view.y = line
	view.zz()
}

// Fit lines  into 80 chars
fn (view mut View) gq() {
	mut vid := view.vid
	if vid.mode != VISUAL {
		return
	}
	view.y_visual()
	max := vid.max_chars(0)
	// Join all selected lines into a single string
	joined := vid.ylines.join('\n')
	// Delete what we selected
	for yline in vid.ylines {
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
	vid.mode = NORMAL
}

fn is_alpha(r byte) bool {
	return ((r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) ||
	(r >= `0` && r <= `9`))
}

fn is_whitespace(r byte) bool {
	return r == ` ` || r == `\t`
}

fn is_alpha_underscore(r int) bool {
	return (is_alpha(r) || byte(r) == `_` || byte(r) == `#` || byte(r) == `$`)
}

fn break_text(s string, max int) []string {
	mut lines := []string
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

