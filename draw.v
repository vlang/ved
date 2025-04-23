module main

import gx
import os

fn (mut ved Ved) draw() {
	mut view := ved.view
	split_width := ved.split_width()
	ved.page_height = ved.win_height / ved.cfg.line_height - 1
	view.page_height = ved.page_height
	// Splits from and to
	from, to := ved.get_splits_from_to()
	// Not a full refresh? Means we need to refresh only current split.
	if !ved.refresh {
		// split_x := split_width * (ved.cur_split - from)
		// ved.gg.draw_rect_filled(split_x, 0, split_width - 1, ved.win_height, ved.cfg.bgcolor)
	}
	// Coords
	y := ved.calc_cursor_y()
	// Cur line
	line_x := split_width * (ved.cur_split - from) + ved.view.padding_left + 10
	line_width := split_width - ved.view.padding_left - 10
	ved.gg.draw_rect_filled(line_x, y, line_width, ved.cfg.line_height, ved.cfg.vcolor)
	// V selection
	mut v_from := ved.view.vstart + 1
	mut v_to := ved.view.vend + 1
	if view.vend < view.vstart {
		// Swap start and end if we go beyond the start
		v_from = ved.view.vend + 1
		v_to = ved.view.vstart + 1
	}
	for yy := v_from; yy <= v_to; yy++ {
		ved.gg.draw_rect_filled(line_x, (yy - ved.view.from) * ved.cfg.line_height, line_width,
			ved.cfg.line_height, ved.cfg.vcolor)
	}
	// Black title background
	ved.gg.draw_rect_filled(0, 0, ved.win_width, ved.cfg.line_height, ved.cfg.title_color)
	// Current split has dark blue title
	// ved.gg.draw_rect_filled(split_x, 0, split_width, ved.cfg.line_height, gx.rgb(47, 11, 105))
	// Title (file paths)
	for i := to - 1; i >= from; i-- {
		v := ved.views[i]
		mut name := v.short_path
		if v.changed && !v.path.ends_with('/out') {
			name = '${name} [+]'
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
	ved.gg.draw_text(ved.win_width - 220, 1, '[${space_name}]', ved.cfg.file_name_cfg)
	ved.gg.draw_text(ved.win_width - 100, 1, '${cur_space}/${nr_spaces}', ved.cfg.file_name_cfg)
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
		task_text_width := ved.cur_task.len * ved.cfg.char_width
		task_x := ved.win_width - split_width - task_text_width - 70
		// ved.timer.gg.draw_text(task_x, 1, ved.timer.cur_task.to_upper(), file_name_cfg)
		ved.gg.draw_text(task_x, 1, ved.cur_task, ved.cfg.file_name_cfg)
		// Draw current task time
		task_time_x := (ved.nr_splits - 1) * split_width - 50
		ved.gg.draw_text(task_time_x, 1, '${ved.task_minutes()}m', ved.cfg.file_name_cfg)
	}
	// Draw pomodoro timer
	if ved.timer.pom_is_started {
		ved.gg.draw_text(split_width - 50, 1, '${ved.pomodoro_minutes()}m', ved.cfg.file_name_cfg)
	}
	// Draw "i" in insert mode
	if ved.mode == .insert {
		ved.gg.draw_text(5, 1, '-i-', ved.cfg.file_name_cfg)
	}
	// Draw "v" in visual mode
	if ved.mode == .visual {
		ved.gg.draw_text(5, 1, '-v-', ved.cfg.file_name_cfg)
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
	// Cur fn name (top right of current split)
	if view.y != view.from { // Don't draw current fn name if the first visible line is selected
		cur_fn_width := ved.cfg.char_width * ved.cur_fn_name.len
		cur_fn_x := (ved.cur_split % ved.nr_splits + 1) * split_width - cur_fn_width - 3
		cur_fn_y := ved.cfg.line_height
		ved.gg.draw_rect(
			x:     cur_fn_x
			y:     cur_fn_y
			w:     cur_fn_width
			h:     ved.cfg.line_height
			color: ved.cfg.bgcolor // gx.rgb(40, 40, 40)
		)
		ved.gg.draw_text(cur_fn_x, cur_fn_y, ved.cur_fn_name, ved.cfg.comment_cfg)
	}
	// Debugger variables
	if ved.mode == .debugger && ved.debugger.output.vars.len > 0 {
		ved.draw_debugger_variables()
	}
	// Cursor
	mut cursor_x := ved.calc_cursor_x()
	ved.draw_cursor(cursor_x, y)

	// ved.gg.draw_text_def(cursor_x + 500, y - 1, 'tab=$cursor_tab_off x=$cursor_x view_x=$ved.view.x')
	// query window
	if ved.mode == .query {
		ved.draw_query()
	} else if ved.mode == .autocomplete {
		ved.draw_autocomplete_window()
	}
	// Big red error line at the bottom
	if ved.error_line != '' {
		ved.gg.draw_rect_filled(0, ved.win_height - ved.cfg.line_height, ved.win_width,
			ved.cfg.line_height, ved.cfg.errorbgcolor)
		ved.gg.draw_text(3, ved.win_height - ved.cfg.line_height, ved.error_line, gx.TextCfg{
			size:  ved.cfg.text_size
			color: gx.white
			align: gx.align_left
		})
	}
	if ved.cfg.show_file_tree {
		// Draw file tree
		ved.tree.draw(mut ved)
	}
}

fn (ved &Ved) split_x(i int) int {
	return ved.split_width() * i
}

fn (mut ved Ved) draw_split(i int, split_from int) {
	view := ved.views[i]
	ved.is_ml_comment = false
	split_width := ved.split_width()
	split_x := split_width * (i - split_from)
	// Vertical split line
	ved.gg.draw_line(split_x, ved.cfg.line_height + 1, split_x, ved.win_height, ved.cfg.split_color)
	// Lines
	mut line_nr := 1 // relative y
	for j := view.from; j < view.from + ved.page_height && j < view.lines.len; j++ {
		line := view.lines[j]
		if line.len > 5000 {
			println('line len too big! views[${i}].lines[${j}] (${line.len}) path=${ved.view.path}')
			continue
		}
		x := split_x + view.padding_left
		y := line_nr * ved.cfg.line_height
		// Error bg
		if view.error_y == j {
			ved.gg.draw_rect_filled(x + 10, y - 1, split_width - view.padding_left - 10,
				ved.cfg.line_height, ved.cfg.errorbgcolor)
		}
		// Breakpoint red circle
		if view.breakpoints.contains(j) {
			ved.gg.draw_circle_filled(split_x + 3, y + ved.cfg.line_height / 2 - 1, 5,
				gx.red)
		}
		// Breakpoint yellow line
		if ved.mode == .debugger && ved.cur_split == i && ved.debugger.output.line_nr != 0
			&& ved.debugger.output.line_nr == j + 1 {
			line_width := split_width - view.padding_left - 10
			ved.gg.draw_rect_filled(x + 10, y, line_width, ved.cfg.line_height, breakpoint_color)
		}
		// Line number
		line_number := j + 1
		ved.gg.draw_text(x + 3, y, '${line_number}', ved.cfg.line_nr_cfg)
		// Tab offset
		mut line_x := x + 10
		mut nr_tabs := 0
		// for k := 0; k < line.len; k++ {
		for c in line {
			if c != `\t` {
				break
			}
			nr_tabs++
			line_x += ved.cfg.char_width * ved.cfg.tab_size
		}
		mut s := line[nr_tabs..] // tabs have been skipped, remove them from the string
		if s == '' {
			line_nr++
			continue
		}
		// Number of chars to display in this view
		// mut max := (split_width - view.padding_left - ved.cfg.char_width * TAB_SIZE *
		// nr_tabs) / ved.cfg.char_width - 1
		max := ved.max_chars(i, nr_tabs)
		if view.y == j {
			// Display entire line if its current
			// if line.len > max {
			// ved.gg.draw_rect_filled(line_x, y - 1, ved.win_width, line_height, vcolor)
			// }
			// max = line.len
		}
		// if s.contains('width :=') {
		// println('"$s" max=$max')
		//}
		// Handle utf8 codepoints
		// old_len := s.len
		if s.len != s.len_utf8() {
			u := s.runes()
			if max > 0 && max < u.len {
				s = u[..max].string()
			}
		} else {
			if max > 0 && max < s.len {
				s = s[..max]
			}
		}
		if view.hl_on {
			// println('line="$s" nrtabs=$nr_tabs line_x=$line_x')
			ved.draw_text_line(line_x, y, s, os.file_ext(view.path))
		} else {
			ved.gg.draw_text(line_x, y, s, ved.cfg.txt_cfg)
		}
		// if old_len != s.len {
		// ved.draw_text_line(line_x, y + 1, '!!!')
		//}
		line_nr++
	}
}

fn (ved &Ved) max_chars(view_idx int, nr_tabs int) int {
	width := ved.split_width() - ved.views[view_idx].padding_left - ved.cfg.char_width * ved.cfg.tab_size * nr_tabs
	return width / ved.cfg.char_width - 1
}

fn (mut ved Ved) add_chunk(typ ChunkKind, start int, end int) {
	chunk := Chunk{
		typ:   typ
		start: start
		end:   end
	}
	ved.chunks << chunk
}

fn (mut ved Ved) draw_text_line(x int, y int, line string, ext string) {
	// mcomment := get_mcomment_by_ext(os.file_ext(ved.view.path))
	mcomment := get_mcomment_by_ext(ext)
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
	cur_syntax := ved.syntaxes[ved.current_syntax_idx] or { Syntax{} }
	// TODO use runes for everything to fix keyword + 2+ byte rune words
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
		// (unless it's /* line */ which is a single line)
		if i > 0 && line[i - 1] == mcomment.start1 && line[i] == mcomment.start2
			&& !(line[line.len - 2] == mcomment.end1 && line[line.len - 1] == mcomment.end2) {
			// All after /* is  a comment
			ved.add_chunk(.a_comment, start, line.len)
			ved.is_ml_comment = true
			break
		}
		// End of /**/
		if i > 0 && line[i - 1] == mcomment.end1 && line[i] == mcomment.end2 {
			// All before */ is still a comment
			ved.add_chunk(.a_comment, 0, start + 1)
			ved.is_ml_comment = false
			break
		}
		// String
		if line[i] == `'` {
			i++
			for i < line.len - 1 && line[i] != `'` {
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
		if word in cur_syntax.literals {
			// println('$word is key')
			ved.add_chunk(.a_lit, start, i)
			// println('adding key. len=$ved.chunks.len')
		} else if word in cur_syntax.keywords {
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
			ved.gg.draw_text(x + pos * ved.cfg.char_width, y, s, ved.cfg.txt_cfg)
		}
		// Keyword, literal, string etc
		typ := chunk.typ
		cfg := match typ {
			.a_key { ved.cfg.key_cfg }
			.a_lit { ved.cfg.lit_cfg }
			.a_string { ved.cfg.string_cfg }
			.a_comment { ved.cfg.comment_cfg }
		}
		s := line[chunk.start..chunk.end]
		ved.gg.draw_text(x + chunk.start * ved.cfg.char_width, y, s, cfg)
		pos = chunk.end
		// Final text chunk
		if i == ved.chunks.len - 1 && chunk.end < line.len {
			final := line[chunk.end..line.len]
			ved.gg.draw_text(x + pos * ved.cfg.char_width, y, final, ved.cfg.txt_cfg)
		}
	}
}
