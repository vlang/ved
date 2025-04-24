// Copyright (c) 2019-2023 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os

struct Mcomment {
	start1 rune
	start2 rune
	end1   rune
	end2   rune
}

fn get_mcomment_by_ext(ext string) Mcomment {
	return match ext {
		//'v', 'go', 'c', 'cpp' {
		// Mcomment{`/`, `*`, `*`, `/`}
		//}
		'.html' {
			Mcomment{`<`, `!`, `-`, `>`}
		}
		else {
			Mcomment{`/`, `*`, `*`, `/`}
		}
	}
}

// Scans the file content *before* the target line number to determine
// if that target line starts inside an unclosed multiline comment block.
fn (ved &Ved) determine_ml_comment_state(view &View, target_line_nr int) bool {
	if target_line_nr <= 0 {
		return false // First line cannot start inside a comment
	}
	mcomment := get_mcomment_by_ext(os.file_ext(view.path))
	// State: true = inside comment, false = outside comment
	mut is_inside := false
	// Scan all lines *before* the target line
	for i := 0; i < target_line_nr; i++ {
		// Basic bounds check, though shouldn't be needed if target_line_nr is valid
		if i >= view.lines.len {
			continue
		}
		line := view.lines[i]
		mut k := 0
		// Scan through the characters of the line
		for k < line.len - 1 {
			// Check for start delimiter "/*" only if we are *outside* a comment
			if !is_inside && line[k] == mcomment.start1 && line[k + 1] == mcomment.start2 {
				is_inside = true // Enter comment state
				k += 2 // Skip the delimiter
				continue
			}
			// Check for end delimiter "*/" only if we are *inside* a comment
			if is_inside && line[k] == mcomment.end1 && line[k + 1] == mcomment.end2 {
				is_inside = false // Exit comment state
				k += 2 // Skip the delimiter
				continue
			}
			// No delimiter found at this position, move to the next character
			k++
		}
	}
	// Return the final state after checking all preceding lines
	return is_inside
}
