// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gg
import time

/*
const txt_cfg = gx.TextCfg{
	size: 18
}
*/

enum QueryType {
	ctrlp            = 0
	search           = 1
	cam              = 2
	open             = 3
	ctrlj            = 4
	task             = 5
	grep             = 6
	open_workspace   = 7
	run              = 8
	alert            = 9 // e.g. "running git pull..."
	search_in_folder = 10
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
				// Re-filter ctrlp results on backspace to update the list immediately
				if ved.query_type == .ctrlp {
					ved.filter_ctrlp_results()
				}
			} else {
				if ved.search_query.len == 0 {
					return
				}
				ved.search_query = ved.search_query[..ved.search_query.len - 1]
			}
			return
		}
		.enter {
			match ved.query_type {
				.ctrlp {
					ved.ctrlp_open()
				}
				.ctrlj {
					ved.ctrlj_open()
				}
				.cam {
					ved.git_commit()
				}
				.open {
					ved.view.open_file(ved.query, 0)
				}
				.task {
					ved.insert_task() or {}
					if !ved.timer.pom_is_started && !ved.cur_task.starts_with('@') {
						// Start pomodoro with a new task if it's not already running
						ved.timer.pom_start = time.now().local_unix()
						ved.timer.pom_is_started = true
					}
					ved.cur_task = ved.query
					ved.task_start_unix = time.now().local_unix()
					ved.save_timer()
				}
				.run {
					ved.run_zsh()
				}
				.grep {
					// Key down was pressed after typing, now pressing enter opens the file
					if ved.gg_pos > -1 && ved.gg_lines.len > 0 && ved.gg_pos < ved.gg_lines.len {
						line := ved.gg_lines[ved.gg_pos]
						path := line.all_before(':')
						pos := line.index(':') or { 0 }
						pos2 := line.index_after(':', pos + 1) or { -1 }
						// line_nr := line[path.len + 1..].int() - 1
						line_nr := line[pos + 1..pos2].int() - 1
						ved.view.open_file(ved.workspace + '/' + path, line_nr)
						// ved.view.move_to_line(line_nr)
						ved.view.zz()
						ved.mode = .normal
					} else {
						// Otherwise just do a git grep on a submitted query
						ved.git_grep()
					}
					return
				}
				else {
					// println('CALLING SEARCH ON ENTER squery=$ved.search_query')
					ved.search(.forward)
				}
			}
			ved.mode = .normal
			return
		}
		.escape {
			ved.mode = .normal
			return
		}
		.down {
			if ved.mode == .query {
				match ved.query_type {
					.grep {
						// Going thru git grep results
						ved.gg_pos++
						if ved.gg_pos >= ved.gg_lines.len {
							ved.gg_pos = ved.gg_lines.len - 1
						}
					}
					.ctrlp {
						ved.gg_pos++
						// Use ctrlp_results length for boundary check
						if ved.gg_pos >= ved.ctrlp_results.len {
							ved.gg_pos = ved.ctrlp_results.len - 1
						}
						if ved.gg_pos < 0 && ved.ctrlp_results.len > 0 { // Handle empty case
							ved.gg_pos = 0
						}
					}
					.search {
						if ved.search_history.len > 0 {
							// History search
							ved.search_idx++
							if ved.search_idx >= ved.search_history.len {
								ved.search_idx = ved.search_history.len - 1
							}
							ved.search_query = ved.search_history[ved.search_idx]
						}
					}
					else {}
				}
			}
		}
		.up {
			if ved.mode == .query {
				match ved.query_type {
					.grep, .ctrlp { // Apply same logic to ctrlp
						ved.gg_pos--
						if ved.gg_pos < 0 {
							ved.gg_pos = 0
						}
					}
					.search {
						if ved.search_history.len > 0 {
							ved.search_idx--
							if ved.search_idx < 0 {
								ved.search_idx = 0
							}
							ved.search_query = ved.search_history[ved.search_idx]
						}
					}
					else {}
				}
			}
		}
		.tab {
			// TODO COPY PASTA - adapt for ctrlp if needed
			if ved.mode == .query {
				match ved.query_type {
					.grep {
						ved.gg_pos++
						if ved.gg_pos >= ved.gg_lines.len {
							ved.gg_pos = 0 // wrap around? or stop?
						}
					}
					.ctrlp {
						ved.gg_pos++
						if ved.gg_pos >= ved.ctrlp_results.len {
							ved.gg_pos = 0 // wrap around? or stop?
						}
					}
					else {}
				}
			}
			ved.just_switched = true
		}
		.v {
			if super {
				clip := ved.cb.paste()
				ved.query += clip
				// Re-filter ctrlp results after paste
				if ved.query_type == .ctrlp {
					ved.filter_ctrlp_results()
				}
			}
		}
		else {}
	}
}

fn (mut ved Ved) char_query(s string) {
	if int(s[0]) < 32 {
		return
	}
	// println('char q(${s}) ${ved.query_type}')
	if ved.query_type in [.search, .search_in_folder, .grep] {
		ved.search_query += s
		println('new sq=${ved.search_query}')
	} else if ved.query_type == .ctrlp {
		ved.query += s
		ved.filter_ctrlp_results() // Filter results as user types
	} else {
		ved.query += s
	}
}

// Loads files for the *current* workspace into `all_git_files`.
fn (mut ved Ved) load_git_tree() {
	ved.query = '' // Reset query when loading tree
	ved.ctrlp_results = [] // Reset ctrlp results as well
	ved.gg_pos = -1

	mut dir := ved.workspace
	if dir == '' {
		dir = '.' // Should not happen if workspace is managed correctly
	}
	if ved.is_git_tree() {
		// Cache all git files for the current workspace
		s := os.execute('git -C ${dir} ls-files')
		if s.exit_code == -1 {
			ved.all_git_files = []
			return
		}
		ved.all_git_files = s.output.split_into_lines()
	} else {
		/*
		// Get all files if not a git repo
		mut files := []string{}
		os.walk_with_context(dir, &files, fn (mut fs []string, f string) {
			if f == '.' || f == '..' {
				return
			}
			full_path := os.join_path(dir, f) // Need full path for is_file check
			if os.is_file(full_path) {
				// Store relative path
				fs << f.replace(dir + os.path_separator, '')
			}
		})
		ved.all_git_files = files
		*/
	}
	ved.all_git_files.sort_by_len()
	// Also filter results initially when Ctrl+P is pressed
	if ved.query_type == .ctrlp {
		ved.filter_ctrlp_results()
	}
}

// Filters files for Ctrl+P based on the current query.
// Searches current workspace first, then others if no results found.
fn (mut ved Ved) filter_ctrlp_results() {
	ved.ctrlp_results = [] // Clear previous results
	ved.gg_pos = -1 // Reset selection
	query_lower := ved.query.to_lower()

	// 1. Search current workspace
	current_ws_path := ved.workspace
	for file_ in ved.all_git_files { // all_git_files should hold current workspace files
		file_path := file_.trim_space()
		if file_path.to_lower().contains(query_lower) {
			ved.ctrlp_results << CtrlPResult{
				file_path:      file_path
				workspace_path: current_ws_path
				display_name:   file_path
			}
			// Limit results early?
			// Stop adding results once we reach the display limit to avoid unnecessary processing
			if ved.ctrlp_results.len >= nr_ctrlp_results {
				return
			}
		}
	}

	// 2. If no results in current workspace and query is not empty, search others
	if ved.ctrlp_results.len == 0 && query_lower != '' {
		for ws_path in ved.workspaces {
			if ws_path == current_ws_path {
				continue // Skip current workspace, already searched
			}
			// Get files for this other workspace (might be slow if not cached)
			other_files := ved.get_files_for_workspace(ws_path)
			short_ws_name := short_space(ws_path)
			for file_path in other_files {
				file_path_trimmed := file_path.trim_space()
				if file_path_trimmed.to_lower().contains(query_lower) {
					ved.ctrlp_results << CtrlPResult{
						file_path:      file_path_trimmed
						workspace_path: ws_path
						display_name:   '${file_path_trimmed} (${short_ws_name})'
					}
					// Limit results early?
					if ved.ctrlp_results.len >= nr_ctrlp_results {
						return
					}
				}
			}
		}
	}

	// Optionally sort results here if needed (e.g., by length, alphabetically)
	// ved.ctrlp_results.sort(...)
}

fn (mut ved Ved) is_git_tree() bool {
	path := if ved.workspace == '' { '.' } else { ved.workspace }

	out := os.execute('git -C "${path}" rev-parse --is-inside-work-tree')
	if out.exit_code != -1 {
		return out.output.trim_space() == 'true' // Ensure comparison is robust
	}

	return false
}

fn (q QueryType) str() string {
	return match q {
		.search { 'find' }
		.search_in_folder { 'find in folder' }
		.ctrlp { 'ctrl p (files)' } // Updated title
		.open { 'open' }
		.open_workspace { 'open workspace' }
		.cam { 'git commit -am' }
		.ctrlj { 'ctrl j (opened files)' }
		.task { 'new task/activity' }
		.grep { 'git grep' }
		.run { 'run a zsh command' }
		.alert { '' }
	}
}

const small_queries = [QueryType.search, .cam, .open, .run, .alert] //.grep

const max_grep_lines = 20
const query_width = 700
const nr_ctrlp_results = 20 // Max results to show for Ctrl+P
const line_padding = 5

// Search, commit, open, ctrl p
fn (mut ved Ved) draw_query() {
	// println('DRAW Q type=$ved.query_type')
	mut width := query_width
	mut height := 360 // Default height

	// Determine fixed height based on query type
	if ved.query_type in small_queries {
		height = 70
	} else if ved.query_type == .grep {
		width *= 2 // Keep grep wide
		// Use fixed height based on max_grep_lines
		height = (max_grep_lines + 2) * (ved.cfg.line_height + line_padding) + 15
	} else if ved.query_type in [.ctrlp, .ctrlj] {
		// Use fixed height based on nr_ctrlp_results
		height = (nr_ctrlp_results + 2) * (ved.cfg.line_height + line_padding) + 15
	}
	// Ensure minimum height
	if height < 70 {
		height = 70
	}

	x := (ved.win_width - width) / 2
	y := (ved.win_height - height) / 2
	ved.gg.draw_rect_filled(x, y, width, height, gg.white)
	// query window title
	ved.gg.draw_rect_filled(x, y, width, ved.cfg.line_height, ved.cfg.title_color)
	ved.gg.draw_text(x + 10, y, ved.query_type.str(), ved.cfg.file_name_cfg)

	query_to_draw := if ved.query_type in [.search, .search_in_folder, .grep] {
		ved.search_query
	} else {
		ved.query
	}

	ved.gg.draw_text(x + 10, y + ved.cfg.line_height, query_to_draw, ved.cfg.txt_cfg)
	// Draw cursor
	cursor_x := x + 10 + query_to_draw.len * ved.cfg.char_width + 1 // cursor
	cursor_y := y + ved.cfg.line_height + 2
	ved.gg.draw_rect(x: cursor_x, y: cursor_y, w: 2, h: ved.cfg.line_height - 4)
	// Draw separator between query and files
	if ved.query_type !in [.search, .cam, .run, .alert] { // Exclude alert too
		ved.gg.draw_rect(
			x:     x
			y:     y + ved.cfg.line_height * 2
			w:     width
			h:     1
			color: ved.cfg.comment_color
		)
	}
	// Draw files/results list
	ved.draw_query_results(ved.query_type, x, y, width) // Pass width
}

// Renamed and generalized function to draw results list
fn (mut ved Ved) draw_query_results(kind QueryType, x int, y int, width int) {
	mut j := 0 // Index for visible item count
	line_y_start := y + ved.cfg.line_height * 2 + line_padding // Start drawing below separator

	match kind {
		.ctrlp {
			// Iterate over the pre-filtered results
			for i, result in ved.ctrlp_results {
				// Stop drawing if we exceed the display limit
				if j >= nr_ctrlp_results {
					break
				}
				yy := line_y_start + (ved.cfg.line_height + line_padding) * j
				if i == ved.gg_pos { // Use index `i` for selection highlight
					ved.gg.draw_rect_filled(x, yy, width, ved.cfg.line_height + line_padding,
						ved.cfg.vcolor)
				}
				ved.gg.draw_text(x + 10, yy + line_padding / 2, result.display_name, ved.cfg.txt_cfg)
				j++
			}
		}
		.grep {
			for i, s in ved.gg_lines {
				if j >= max_grep_lines { // Use grep limit
					break
				}
				yy := line_y_start + (ved.cfg.line_height + line_padding) * j
				if i == ved.gg_pos {
					ved.gg.draw_rect_filled(x, yy, width, ved.cfg.line_height + line_padding,
						ved.cfg.vcolor) // Use passed width
				}
				pos := s.index(':') or { continue }
				path := s[..pos].limit(55)
				pos2 := s.index_after(':', pos + 1) or { -1 }
				if pos2 == -1 || pos2 >= s.len - 1 {
					continue
				}
				text := s[pos2 + 1..].trim_space().limit(100)
				line_nr := s[pos + 1..pos2]
				// Draw path and line number
				ved.gg.draw_text2(
					x:     x + 10
					y:     yy + line_padding / 2
					text:  path.limit(50) + ':${line_nr}'
					color: gg.purple
				)
				// Draw matching text part (adjust x position)
				text_x := x + 10 + (path.limit(50).len + 1 + line_nr.len + 2) * ved.cfg.char_width // Approximate position
				ved.gg.draw_text(text_x, yy + line_padding / 2, text, ved.cfg.txt_cfg)
				j++
			}
		}
		.ctrlj {
			// TODO: Implement drawing for ctrlj if needed, similar to ctrlp
			// using ved.open_paths[ved.workspace_idx]
		}
		else {
			// No list for other query types
		}
	}
}

// Open file on enter for Ctrl+P
fn (mut ved Ved) ctrlp_open() {
	println('ctrlpopen gg_pos=${ved.gg_pos}')
	if ved.gg_pos < 0 || ved.gg_pos >= ved.ctrlp_results.len {
		println(1)
		// Attempt to open if only one result and selection is invalid (e.g., -1)
		// if ved.ctrlp_results.len == 1 {
		println('set to 0')
		ved.gg_pos = 0
		//} else {
		// println('invalid index')
		// return // Invalid selection index
		//}
	}
	// Get the selected result
	selected_result := ved.ctrlp_results[ved.gg_pos]

	// Construct the full path using the result's workspace and file path
	full_path := os.join_path(selected_result.workspace_path, selected_result.file_path)

	// Open the file in the current view
	// This might open a file from another workspace in the current view's split.
	// Consider if a workspace switch is desired later.
	ved.view.open_file(full_path, 0)

	// Reset state after opening
	ved.gg_pos = -1
	ved.query = ''
	ved.ctrlp_results = []
	ved.save_session() // Save session as a file was potentially opened/switched
}

// TODO merge with fn above
fn (mut ved Ved) ctrlj_open() {
	// Ensure gg_pos is valid for the open_paths list
	current_open_paths := ved.open_paths[ved.workspace_idx]
	if ved.gg_pos < 0 || ved.gg_pos >= current_open_paths.len {
		// Attempt to open if only one result and selection is invalid
		if current_open_paths.len == 1 && ved.query == '' { // Assuming only one open file if query is empty
			ved.gg_pos = 0
		} else {
			// Need filtering logic here if query is used for ctrlj
			return
		}
	}

	// Filter open paths based on query to find the actual selected path
	// (gg_pos relates to the *filtered* list shown, not the full list)
	// This part needs careful implementation matching how ctrlj filtering works.
	// Simple filtering for demonstration:
	mut filtered_paths := []string{}
	for p in current_open_paths {
		if p.to_lower().contains(ved.query.to_lower()) {
			filtered_paths << p
		}
	}

	if ved.gg_pos < 0 || ved.gg_pos >= filtered_paths.len {
		return
	}

	selected_relative_path := filtered_paths[ved.gg_pos].trim_space()

	if selected_relative_path == '' {
		return
	}

	// Construct full path (assuming ctrlj shows files relative to current workspace)
	mut space := ved.workspace
	if space == '' {
		space = '.'
	}
	full_path := os.join_path(space, selected_relative_path)
	ved.view.open_file(full_path, 0)

	// Reset state
	ved.gg_pos = -1
	ved.query = ''
	ved.save_session()
}

fn (mut ved Ved) git_grep() {
	ved.gg_pos = 0 // select the first result for faster switching to the right file =
	// (especially if there's only one result)
	query := ved.search_query.replace('$', '\\\$')
	s := os.execute('git -C "${ved.workspace}" grep -F -n "${query}"')
	if s.exit_code == -1 {
		return
	}
	lines := s.output.split_into_lines()
	ved.gg_lines = []
	top_loop: for line in lines {
		if line.contains('thirdparty/') {
			continue
		}
		if line.contains('LICENSE:') {
			continue
		}
		if line.contains('Binary file ') && line.contains(' matches') {
			continue
		}
		// Handle grep file extensions to filter (defined in .ved file per workspace)
		if ved.grep_file_exts[ved.workspace].len > 0 {
			for ext in ved.grep_file_exts[ved.workspace] {
				if !line.contains('.${ext}:') {
					continue top_loop
				}
			}
		}
		ved.gg_lines << line
	}
}

enum SearchType {
	backward
	forward
}

fn (mut ved Ved) search(search_type SearchType) {
	println('search() query=${ved.search_query}')
	if ved.search_query == '' {
		return
	}
	mut view := ved.view
	mut to := view.lines.len
	mut di := 1
	goback := search_type == .backward
	start_line := if goback { view.y - 1 } else { view.y + 1 } // Start search from next/prev line

	if search_type == .backward {
		to = -1 // Go down to index 0
		di = -1
	}

	// First pass: from start_line to end/beginning of file
	for i := start_line; true; i += di {
		if (goback && i <= to) || (!goback && i >= to) {
			break // Reached end/beginning
		}
		if i >= view.lines.len || i < 0 { // Bounds check
			continue
		}

		line := view.lines[i]
		if pos := line.index(ved.search_query) {
			// Found
			if i >= view.from && i < view.from + ved.page_height { // Check < page_height
				ved.prev_y = view.y
				view.set_y(i)
			} else {
				ved.move_to_line(i)
			}
			view.x = pos
			ved.add_to_search_history() // Add to history upon successful find
			return
		}
	}

	// Second pass (wrap around): from beginning/end to original line
	start_wrap := if goback { view.lines.len - 1 } else { 0 }
	end_wrap := if goback { view.y } else { view.y } // Search up to original line

	for i := start_wrap; true; i += di {
		if (goback && i < end_wrap) || (!goback && i > end_wrap) {
			break // Reached original line
		}
		if i >= view.lines.len || i < 0 { // Bounds check
			continue
		}

		line := view.lines[i]
		if pos := line.index(ved.search_query) {
			// Found on wrap
			if i >= view.from && i < view.from + ved.page_height {
				ved.prev_y = view.y
				view.set_y(i)
			} else {
				ved.move_to_line(i)
			}
			view.x = pos
			ved.add_to_search_history() // Add to history upon successful find
			return
		}
	}

	// If still not found and searching in folder is enabled
	if ved.search_dir != '' && search_type == .forward { // Only support forward search in folder for now
		ext := '.' + ved.view.path.after('.')
		// Ensure search_dir exists and is a directory
		if !os.is_dir(ved.search_dir) {
			println('Search directory "${ved.search_dir}" not found or is not a directory.')
			ved.search_dir = '' // Reset search dir if invalid
			return
		}
		files := os.walk_ext(ved.search_dir, ext) // Use the specified search_dir
		current_file_index := files.index(ved.view.path) // Find index of current file

		for i := current_file_index + 1; i < files.len; i++ { // Start from file *after* current
			file_path := files[i]
			if file_path == ved.view.path {
				continue
			}
			// Should not happen, but safe check

			text := os.read_file(file_path) or {
				println('Error reading file: ${file_path}')
				continue // Skip file if cannot read
			}
			if _ := text.index(ved.search_query) {
				ved.view.open_file(file_path, 0) // Open the new file
				// Now perform a search within the newly opened file to find the first match
				ved.search(search_type) // Recursive call to find position in the new file
				ved.add_to_search_history() // Add to history
				return
			}
		}
		// If search reaches end of directory without finding, maybe wrap around? (Optional)
		println('Search query "${ved.search_query}" not found in folder "${ved.search_dir}".')
	} else {
		println('Search query "${ved.search_query}" not found in current file.')
	}
}

// Helper to add query to history only if it's new
fn (mut ved Ved) add_to_search_history() {
	if ved.search_query != ''
		&& (ved.search_history.len == 0 || ved.search_history.last() != ved.search_query) {
		ved.search_history << ved.search_query
		ved.search_idx = ved.search_history.len // Point index past the end for new searches
	}
}

fn (ved &Ved) load_all_tasks() {
	/*
        mut rows := ved.timer.db.q_strings('select distinct name from tasks')
        for row in rows {
                t := row.vals[0]
                ved.top_tasks << t
        }
        println(ved.top_tasks)
        */
}
