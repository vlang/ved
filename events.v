module main

import os
import gg

fn key_down(key gg.KeyCode, mod gg.Modifier, mut ved Ved) {
	super := mod == .super
	if key == .escape {
		if ved.mode == .visual {
			ved.exit_visual()
		}
		ved.mode = .normal
	}
	// Reset error line
	ved.view.error_y = -1
	ved.error_line = ''
	match ved.mode {
		.normal { ved.key_normal(key, mod) }
		.visual { ved.key_visual(key, mod) } // Pass full mod
		.insert { ved.key_insert(key, mod) }
		.query { ved.key_query(key, super) }
		.timer { ved.timer.key_down(key, super) }
		.autocomplete { ved.key_insert(key, mod) }
		.debugger { ved.key_normal(key, mod) }
	}
	ved.gg.refresh_ui()
}

fn (mut ved Ved) key_normal(key gg.KeyCode, mod gg.Modifier) {
	super := mod == .super || mod == .ctrl
	shift := mod == .shift
	// println('mod=')
	// println(int(mod))
	shift_and_super := int(mod) == 9
	mut view := ved.view
	ved.refresh = true
	if ved.prev_key == .r {
		return
	}
	if ved.prev_cmd == 'ci' {
		println('CALLING CI PREV S=${ved.prev_key_str}')
		view.ci(key)
		return
	}
	match key {
		.enter {
			// Full screen => window
			// Update screen size
			if super {
				println('full screen')
				width, height := get_screen_size()

				// ved.nr_splits = 1
				ved.win_width = width
				ved.win_height = height
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
			} else if super {
				//
				// ved.cfg.reload_config()
				// ved.update_view()
			}
		}
		.slash {
			ved.search_query = ''
			ved.mode = .query
			ved.just_switched = true
			ved.search_dir = ''
			if shift {
				ved.query_type = .grep
			} else if super {
				ved.query_type = .search_in_folder
				ved.search_dir = os.dir(ved.view.path)
			} else {
				ved.query_type = .search
			}
		}
		.f5 {
			ved.run_file()
			// ved.cfg.char_width -= 1
			// ved.cfg.line_height -= 1
			// ved.font_size -= 1
			// ved.page_height = WIN_HEIGHT / ved.cfg.line_height - 1
			// case C.GLFW_KEY_F6:
			// ved.cfg.char_width += 1
			// ved.cfg.line_height += 1
			// ved.font_size += 1
			// ved.page_height = WIN_HEIGHT / ved.cfg.line_height - 1
			// ved.vg = gg.new_context(WIN_WIDTH, WIN_HEIGHT, ved.font_size)
		}
		.minus {
			if shift_and_super {
				// println('FONT DECREASE')
				ved.increase_font(-1)
			} else if super {
				ved.get_git_diff_full()
			}
		}
		.equal {
			if shift {
				ved.prev_key = .equal
			} else if shift_and_super {
				ved.increase_font(1)
				// println('FONT INCREASE')
			}
		}
		.f12 {
			if shift {
				ved.open_blog()
			}
		}
		.apostrophe {
			if ved.prev_key == .apostrophe {
				ved.prev_key = gg.KeyCode.invalid
				ved.move_to_line(ved.prev_y)
				return
			}
		}
		._0 {
			if super {
				// new task
				ved.query = ''
				ved.mode = .query
				ved.query_type = .task
				ved.just_switched = true
			}
		}
		._9 {
			if super {
				// new @task
				ved.query = '@'
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
			} else if super {
				// ctrl+a - increase number
				ved.view.super_a(1)
				ved.prev_cmd = 'a'
			}
		}
		.c {
			if super {
				ved.query = ''
				ved.mode = .query
				ved.query_type = .cam
				ved.just_switched = true
			} else if shift {
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
			if ved.mode == .debugger {
				ved.debugger.step_over()
			} else if shift {
				// backwards search
				ved.search(.backward)
			} else {
				ved.search(.forward)
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
				ved.mode = .query
				ved.query_type = .alert
				ved.query = 'Running git pull...'
				ved.just_switched = true
				spawn ved.git_pull()
				return
			} else if super {
				ved.mode = .query
				ved.query_type = .ctrlp
				ved.load_git_tree() // TODO only run if files change
				ved.query = ''
				ved.just_switched = true
				return
			} else {
				view.p()
			}
		}
		.r {
			if shift_and_super {
				ved.query = ''
				ved.mode = .query
				ved.query_type = .run
				ved.just_switched = true
			} else if super {
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
			} else {
				ved.view.h()
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
		.f6 {}
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
					ved.prev_key = .invalid // so that e.g. "ggd" doesn't trigger "gd" (go to def) TODO do this for each multi key command?
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
			if shift_and_super {
				ved.view.add_breakpoint(ved.view.y)
			} else if super {
				// force crash
				// # void*a = 0; int b = *(int*)a;
				ved.view.shift_b()
			} else {
				if ved.prev_key == .d {
					view.db(true)
				} else {
					ved.view.b()
				}
			}
		}
		.u {
			if shift_and_super {
				ved.mode = .debugger
				ved.run_debugger(ved.view.breakpoints)
			} else if super {
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
			if super {
				// ctrl+x - decrease number
				ved.view.super_a(-1)
				ved.prev_cmd = 'x'
			} else {
				ved.view.delete_char()
			}
		}
		.y {
			if ved.prev_key == .y {
				ved.view.yy()
			}
			if super {
				spawn ved.build_app2()
			}
		}
		.z {
			if ved.prev_key == .z {
				ved.view.zz()
			}
			// Next workspace
		}
		// ]
		.right_bracket {
			if super {
				ved.open_workspace(ved.workspace_idx + 1)
			}
		}
		// [
		.left_bracket {
			if super {
				ved.open_workspace(ved.workspace_idx - 1)
			} else if ved.prev_key == .left_bracket {
				ved.go_to_fn_start()
				println('[[ !!!!!')
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
		._5 {
			if shift {
				ved.pct()
			}
		}
		else {}
	}
	if key != .r {
		// otherwise R is triggered when we press C-R
		ved.prev_key = key
	}
	if key == .q && super {
		ved.cq_in_a_row++
	} else {
		ved.cq_in_a_row = 0
	}
	if ved.cq_in_a_row == 2 {
		exit(0)
	}
}

@[manualfree]
fn on_char(code u32, mut ved Ved) {
	if ved.just_switched {
		ved.just_switched = false
		return
	}
	mut buf := [5]u8{}
	s := unsafe { utf32_to_str_no_malloc(code, mut &buf[0]) }
	// s := utf32_to_str(code)
	// println('s="$s" code="$code"')
	match ved.mode {
		.insert, .autocomplete {
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
					ved.prev_key = gg.KeyCode.invalid
					ved.prev_cmd = 'r'
					ved.prev_insert = s.clone()
				}
				return
			}
			ved.prev_key_str = s // for `ci(` etc, no `(` in gg.KeyCode
		}
		else {}
	}
}

fn (mut ved Ved) key_insert(key gg.KeyCode, mod gg.Modifier) {
	super := mod == .super || mod == .ctrl
	// shift := mod == .shift
	match key {
		.backspace {
			ved.just_switched = true // prevent backspace symbol being added in char handler
			ved.view.backspace()
		}
		.enter {
			if false && ved.mode == .autocomplete {
				// Pressed enter in autocomplete mode, insert text from selected suggested field
				ved.insert_suggested_field()
			} else {
				ved.view.enter()
			}
		}
		.escape {
			ved.mode = .normal
		}
		.tab {
			line := ved.view.line()
			if line.ends_with('p ') {
				ved.view.insert_text("rintln('')")
				ved.view.x -= 2
			} else {
				ved.view.insert_text('\t')
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

fn (mut ved Ved) char_insert(s string) {
	if int(s[0]) < 32 {
		return
	}
	ved.view.insert_text(s)
	ved.prev_insert += s
	// println(ved.prev_insert)
}

fn (mut ved Ved) key_visual(key gg.KeyCode, mod gg.Modifier) {
	super := mod == .super || mod == .ctrl
	shift := mod == .shift
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
			ved.view.j() // Move the cursor down as well (mimics vim's behavior)
		}
		.k {
			if view.vend > 0 {
				view.vend--
			}
			ved.view.k() // Move the cursor up as well (mimics vim's behavior)
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
				// <
				ved.view.shift_left()
			}
		}
		.g { // Handle 'g' in visual mode
			if shift { // G key
				// Select to end of file
				if view.lines.len > 0 {
					view.vend = view.lines.len - 1
					view.set_y(view.vend) // Move cursor to last line
					// Scroll view to show the end
					view.from = if view.vend > view.page_height {
						view.vend - view.page_height + 1
					} else {
						0
					}
				}
				ved.prev_key = .invalid // Reset potential double-key sequence
				return
			} else if ved.prev_key == .g { // gg key (Select to start of file)
				view.vend = 0 // Select up to the first line (index 0)
				view.set_y(0) // Move cursor to the first line
				view.from = 0 // Ensure the top of the file is visible
				ved.prev_key = .invalid // Reset the double-key state
				return
			}
		}
		// Page Down handling
		.page_down, .f {
			if key == .f && !super {
				// Only handle Ctrl+F for page down
				return
			}
			view.shift_f() // Move view and cursor
			view.vend = view.y // Extend selection to new cursor position
		}
		// Page Up handling
		.page_up, .b {
			if key == .b && !super {
				// Only handle Ctrl+B for page up
				return
			}
			view.shift_b() // Move view and cursor
			view.vend = view.y // Extend selection to new cursor position
		}
		else {}
	} // end match key

	// Default prev_key handling (only if the key wasn't part of a completed sequence like gg or G)
	if key != .r { // Keep the existing check for 'r'
		ved.prev_key = key
	}
}
