// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.

module main
import os
 

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
	ctx          *Vid
	prev_y       int
	hash_comment bool
	hl_on        bool
}

fn (ctx &Vid) new_view() View {
	res := View {
		padding_left: 0 
		path: '' 
		from: 0 
		y: 0 
		x: 0 
		prev_x: 0 
		page_height: ctx.page_height 
		vstart: -1 
		vend: -1 
		ctx: ctx 
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
		word := line.substr(start2, i)
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
	mut ctx := view.ctx
	mut is_new := false
	if path != view.path {
		is_new = true
		// Save cursor pos (Y)
		// view.ctx.file_y_pos.set(view.path, view.y)
		view.prev_path = view.path
	}
	view.lines = os.read_lines(path)
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
				if !ctx.words.contains(word) {
					ctx.words << word
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
	view.short_path = path.replace(DefaultDir, '')
	if view.short_path.starts_with('/') {
		view.short_path = view.short_path.right(1)
	}
	// Calc padding_left
	nr_lines := view.lines.len
	s := '$nr_lines'
	view.padding_left = s.len * ctx.char_width + 8
	view.ctx.save_session()
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
		y := view.ctx.file_y_pos[view.path]
		if y > 0 {
			view.y = y
		}
	}
	view.hash_comment = !view.path.ends_with('.v')
	view.hl_on = !view.path.ends_with('.md')
}

fn (view mut View) reopen() {
	view.open_file(view.path)
}

fn (view mut View) save_file() {
	if view.path == '' {
		return
	}
	path := view.path
	println('saving file "$path"')
	println('lines.len=$view.lines.len')
	line0 := view.lines[0]
	println('line[0].len=$line0.len')
	file := os.create(path) or {
		panic('fail')
	}
	for line in view.lines {
		file.writeln(line)
	}
	file.close()
	// Run formatters 
	if path.ends_with('.go') {
		println('calling go imports')
		os.system('goimports -w "$path"')
	}
	if path.ends_with('.scss') {
		css := path.replace('.scss', '.css')
		os.system('sassc "$path" > "$css"')
	}
	view.reopen()
	// update git diff
	view.ctx.get_git_diff()
	view.changed = false
	println('end of save file()')
	println('_lines.len=$view.lines.len')
	line0_ := view.lines[0]
	println('_line[0].len=$line0_.len')
}

fn (view &View) line() string {
	if view.y >= view.lines.len {
		return ''
	}
	return view.lines[view.y]
}

fn (view &View) uline() ustring {
	return view.line().ustring()
}

fn (view &View) char() int {
	line := view.line()
	return int(line[view.x])
}

fn (view mut View) set_line(newline string) {
	// # view->lines.data[view->y] = newline;
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

fn (view mut View) H() {
	view.y = view.from
}

fn (view mut View) move_to_page_bot() {
	view.y = view.from + view.page_height - 1
}

fn (view mut View) l() {
	line := view.lines[view.y]
	// line := view.line()
	if view.x < line.len - 1 {
		view.x++
	}
}

fn (view mut View) G() {
	view.y = view.lines.len - 1
	view.from = view.y - view.page_height + 1
	if view.from < 0 {
		view.from = 0
	}
}

fn (view mut View) A() {
	line := view.line()
	view.set_line('$line ')
	view.x = view.uline().len - 1
}

fn (view mut View) I() {
	view.x = 0
	for view.char() == TAB {
		view.x++
	}
}

fn (view mut View) gg() {
	view.from = 0
	view.y = 0
}

fn (view mut View) F() {
	view.from += view.page_height
	if view.from >= view.lines.len {
		view.from = view.lines.len - 1
	}
	view.y = view.from
}

fn (view mut View) B() {
	view.from -= view.page_height
	if view.from < 0 {
		view.from = 0
	}
	view.y = view.from
}

fn (view mut View) dd() {
	mut ctx := view.ctx
	ctx.prev_key = -1
	ctx.prev_cmd = 'dd'
	ctx.ylines = []string{}
	ctx.ylines << view.line()
	view.lines.delete(view.y)
	view.changed = true
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
		view.set_line(line.right(1))
		return
	}
	for i := view.vstart; i <= view.vend; i++ {
		line := view.lines[i]
		if !line.starts_with('\t') {
			continue
		}
		view.lines[i] = (line.right(1))
	}
}

fn (v mut View) delete_char() {
	u := v.uline()
	if v.x < u.len - 1 {
		left := u.left(v.x)
		right := u.right(v.x + 1)
		v.set_line('${left}${right}')
	} 
}

fn (view mut View) C() string {
	line := view.line()
	s := line.left(view.x)
	deleted := line.right(view.x)
	view.set_line('${s} ')
	view.x = s.len
	return deleted
}

fn (view mut View) insert_text(s string) {
	mut line := view.line()
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
		left := uline.substr(0, view.x)
		right := uline.substr(view.x, uline.len)
		// Insert chat in the middle
		res := '${left}${s}${right}'
		view.set_line(res)
	}
	view.x += s.ustring().len
	view.changed = true
}

fn (view mut View) backspace() {
	if view.x == 0 {
		return
	}
	uline := view.uline()
	left := uline.left(view.x - 1)
	right := uline.right(view.x)
	view.set_line('${left}${right}')
	view.x--
}

fn (view mut View) yy() {
	mut ctx := view.ctx
	mut ylines := []string{}
	ylines << (view.line())
	ctx.ylines = ylines
}

fn (view mut View) p() {
	for line in view.ctx.ylines {
		view.o()
		view.set_line(line)
	}
}

fn (view mut View) o() {
	// view.lines.push('')
	view.y++
	lines := view.lines
	// lines.insert(view.y, '')
	view.lines = lines
	empty := ''
	if view.y >= view.lines.len {
		view.lines << ''
	}
	else {
		view.lines.insert(view.y, empty)
	}
	view.x = 0
	// Insert the same amount of spaces as on prev line
	// for view.X < len(view.lines[view.Y-1]) && view.lines[view.Y-1][view.X] == ' ' {
	// view.X++
	// view.lines[view.Y] += " "
	// }
	view.changed = true
}

fn (view mut View) enter() {
	// Create new line
	// And move everything to the right of the cursor to it
	pos := view.x
	line := view.line()
	if line == '' {
		view.o()
		return
	}
	uline := line.ustring()
	right := uline.right(pos)
	left := uline.left(pos)
	view.set_line(left)
	view.o()
	view.set_line(right)
	view.x = 0
	// {} insertion
	prev_line := view.lines[view.y - 1]
	if prev_line.len > 0 {
		last_char := prev_line[prev_line.len - 1]
		if prev_line.len > 0 && last_char == `{` {
			view.o()
			view.insert_text('}')
			view.y--
			view.x = 0
		}
	}
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
	mut ylines := []string{}
	for i := v.vstart; i <= v.vend; i++ {
		ylines << v.lines[i]
	}
	mut ctx := v.ctx
	ctx.ylines = ylines
	// Copy YY to clipboard TODO
	// mainWindow.SetClipboardString(strings.Join(ylines, "\n"))
	v.vstart = -1
	v.vend = -1
}

fn (view mut View) d_visual() {
	view.y_visual()
	for i := 0; i < view.ctx.ylines.len; i++ {
		view.lines.delete(view.y)
	}
}

fn (view mut View) cw() {
	mut ctx := view.ctx
	view.dw()
	ctx.prev_cmd = 'cw'
	view.ctx.set_insert()
}

fn (view mut View) dw() {
	mut ctx := view.ctx
	typ := is_alpha(view.char())
	// While cur char has the same type - delete it
	for {
		line := view.line()
		// println('line=$line x=$view.x')
		if view.x >= 0 && view.x < line.len &&
		typ == is_alpha(view.char()) {
			view.delete_char()
		}
		else {
			break
		}
	}
	ctx.prev_cmd = 'dw'
}

// TODO COPY PASTA
// same as cw but deletes underscores
fn (view mut View) ce() {
	mut ctx := view.ctx
	view.de()
	ctx.prev_cmd = 'ce'
	view.ctx.set_insert()
}

fn (view mut View) w() {
	line := view.line()
	typ := is_alpha_underscore(view.char())
	// Go to end of current word
	for view.x < line.len && typ == is_alpha_underscore(view.char()) {
		view.x++
	}
	// Go to start of next word
	for view.x < line.len && view.char() == 32 {
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
	mut ctx := view.ctx
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
	ctx.prev_cmd = 'de'
}

fn (view mut View) zz() {
	view.from = view.y - view.ctx.page_height / 2
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
	mut ctx := view.ctx
	ctx.prev_key = -1
	view.open_file(view.prev_path)
}

fn (view mut View) move_to_line(line int) {
	view.from = line
	view.y = line
	view.zz()
}

// Fit lines  into 80 chars
fn (view mut View) gq() {
	mut ctx := view.ctx
	if ctx.mode != VISUAL {
		return
	}
	view.y_visual()
	max := ctx.max_chars(0)
	// Join all selected lines into a single string
	joined := ctx.ylines.join('\n')
	// Delete what we selected
	for yline in ctx.ylines {
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
	ctx.mode = NORMAL
}

fn is_alpha(r byte) bool {
	return ((r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || 
	(r >= `0` && r <= `9`))
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
			lines << s.substr(start, i + 1)
			break
		}
		if i - start >= max {
			lines << s.substr(start, i)
			start = i
		}
	}
	return lines
}

