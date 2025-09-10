// Copyright (c) 2019-2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import strings

// Fit lines  into 80 chars
// gq reflows (formats) the visually selected paragraph to a fixed width. (Vim: `gq`)
fn (mut view View) gq() {
	mut ved := view.ved
	if ved.mode != .visual {
		return
	}

	vtop, vbot := if view.vstart < view.vend {
		view.vstart, view.vend
	} else {
		view.vend, view.vstart
	}
	if vtop < 0 || vbot < 0 || vtop >= view.lines.len || vbot >= view.lines.len {
		ved.exit_visual()
		return
	}

	mut selected_lines := []string{}
	for i := vtop; i <= vbot; i++ {
		selected_lines << view.lines[i]
	}

	if selected_lines.len == 0 {
		ved.exit_visual()
		return
	}

	// Preserve indentation from the first line of the selection.
	first_line := selected_lines[0]
	indent_str := first_line[..first_line.len - first_line.trim_left(' \t').len]

	// Combine selected lines into a single string, preserving paragraph breaks (empty lines).
	mut paragraphs := []string{}
	mut current_paragraph := strings.new_builder(1024)
	for line in selected_lines {
		trimmed_line := line.trim_space()
		if trimmed_line.len == 0 {
			if current_paragraph.len > 0 {
				paragraphs << current_paragraph.str()
				unsafe {
					current_paragraph.reset()
				}
			}
			paragraphs << '' // Represents a blank line
		} else {
			if current_paragraph.len > 0 {
				current_paragraph.write_string(' ')
			}
			current_paragraph.write_string(trimmed_line)
		}
	}
	if current_paragraph.len > 0 {
		paragraphs << current_paragraph.str()
	}

	// Delete the original selected lines.
	for i := 0; i < selected_lines.len; i++ {
		view.lines.delete(vtop)
	}

	// Reflow each paragraph and build the final list of new lines.
	max_width := 79
	reflow_width := max_width - indent_str.runes().len

	mut new_lines := []string{}
	for para in paragraphs {
		if para == '' {
			new_lines << indent_str.trim_right(' \t')
		} else {
			reflowed_para := reflow_text_word_aware(para, if reflow_width > 10 {
				reflow_width
			} else {
				10
			})
			for line in reflowed_para {
				new_lines << indent_str + line
			}
		}
	}

	// Insert the new, reflowed lines back into the buffer one by one.
	mut insert_pos := if vtop > view.lines.len { view.lines.len } else { vtop }
	for line in new_lines {
		if insert_pos > view.lines.len { // Should not happen, but a safeguard
			view.lines << line
		} else {
			view.lines.insert(insert_pos, line)
		}
		insert_pos++
	}

	// Reset cursor and mode.
	view.set_y(vtop)
	view.x = indent_str.runes().len
	ved.exit_visual()
	view.changed = true
}

fn reflow_text_word_aware(text string, width int) []string {
	mut lines := []string{}
	// Normalize newlines and whitespace, then split into words.
	words := text.replace('\n', ' ').split(' ').filter(it.len > 0)

	if words.len == 0 {
		return lines
	}

	mut current_line := strings.new_builder(width)

	for word in words {
		// If the current line is empty, just add the word.
		if current_line.len == 0 {
			current_line.write_string(word)
			// If adding the word (with a space) fits, add it.
		} else if current_line.len + 1 + word.len <= width {
			current_line.write_string(' ')
			current_line.write_string(word)
			// Otherwise, finish the current line and start a new one with the word.
		} else {
			lines << current_line.str()
			unsafe {
				current_line.reset()
			}
			current_line.write_string(word)
		}
	}

	// Add the last line if it has content.
	if current_line.len > 0 {
		lines << current_line.str()
	}

	return lines
}
