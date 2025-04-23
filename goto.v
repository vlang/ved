module main

import os

// gd
fn (mut ved Ved) go_to_def() {
	word := ved.word_under_cursor()
	// println('GD "$word"')
	queries := [') ${word}(', 'fn ${word}(']
	mut view := ved.view
	for query in queries {
		for i, line in view.lines {
			if line.contains(query) {
				ved.move_to_line(i)
				return
			}
		}
	}
	// Not found in current file, try all files in the git tree
	if ved.all_git_files.len == 0 {
		// ctrl p not pressed, force to generate all git files list
		ved.load_git_tree()
	}
	for query in queries {
		for file_ in ved.all_git_files {
			mut file := file_.to_lower()
			file = file.trim_space()
			if !file.ends_with('.v') {
				continue
			}
			file = '${ved.workspace}/${file}'
			lines := os.read_lines(file) or { continue }
			// println('trying file $file with $lines.len lines')
			for j, line in lines {
				if line.contains(query) {
					view.open_file(file, j)
					// ved.move_to_line(j)
					return
				}
			}
		}
	}
}

// Implements the `[[` command, moving the cursor to the start of the current or preceding function definition.
fn (mut ved Ved) go_to_fn_start() {
	mut view := ved.view
	// Start checking from the line *above* the current cursor position
	mut current_line_nr := view.y - 1

	for current_line_nr >= 0 {
		// Ensure we don't access an invalid index if the file is empty or near the beginning
		if current_line_nr < view.lines.len {
			line := view.lines[current_line_nr]
			// Check if the line starts with "fn " (V function definition)
			// TODO: Potentially add checks for other languages like Go ("func ") if needed
			if line.starts_with('fn ') {
				ved.move_to_line(current_line_nr)
				view.zz() // Center the view on the found function
				return
			}
		}
		current_line_nr--
	}
	// If no function start is found above, potentially move to the top of the file or do nothing.
	// Current behavior: do nothing if no function found above.
}