// Copyright (c) 2019-2023 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os

// For syntax highlighting
enum ChunkKind {
	a_string  = 1
	a_comment = 2
	a_key     = 3
	a_lit     = 4
}

struct Chunk {
	start int
	end   int
	typ   ChunkKind
}

struct Mcomment {
	start string
	end   string
}

fn (mut ved Ved) add_chunk(typ ChunkKind, start int, end int) {
	chunk := Chunk{
		typ:   typ
		start: start
		end:   end
	}
	ved.chunks << chunk
}

// Updated to use the new Mcomment struct
fn get_mcomment_by_ext(ext string) Mcomment {
	return match ext {
		'.html' {
			Mcomment{
				start: '<!--'
				end:   '-->'
			}
		}
		else {
			Mcomment{
				start: '/*'
				end:   '*/'
			}
		}
	}
}

// Scans the file content *before* the target line number to determine
// if that target line starts inside an unclosed multiline comment block.
// Updated to use string-based delimiters.
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
		for k < line.len {
			// Check for start delimiter only if we are *outside* a comment
			if !is_inside && k + mcomment.start.len <= line.len
				&& line[k..k + mcomment.start.len] == mcomment.start {
				is_inside = true // Enter comment state
				k += mcomment.start.len // Skip the delimiter
				continue
			}
			// Check for end delimiter only if we are *inside* a comment
			if is_inside && k + mcomment.end.len <= line.len
				&& line[k..k + mcomment.end.len] == mcomment.end {
				is_inside = false // Exit comment state
				k += mcomment.end.len // Skip the delimiter
				continue
			}
			// No delimiter found at this position, move to the next character
			k++
		}
	}
	// Return the final state after checking all preceding lines
	return is_inside
}

// Handles syntax highlighting for a line assuming it does *not* start within a multi-line comment
// and does *not* start a multi-line comment that continues to the next line.
// It handles single-line comments (//, #), strings, keywords, literals, and single-line /* ... */ or <!-- ... --> comments.
fn (mut ved Ved) draw_text_line_standard_syntax(x int, y int, line string, ext string) {
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

	ved.chunks = []
	cur_syntax := ved.syntaxes[ved.current_syntax_idx] or { Syntax{} }
	// TODO use runes for everything to fix keyword + 2+ byte rune words

	mut i := 0 // Use mut i instead of for loop index to allow manual increment
	for i < line.len {
		start := i
		// Comment // #
		if i > 0 && line[i - 1] == `/` && line[i] == `/` {
			ved.add_chunk(.a_comment, start - 1, line.len)
			i = line.len // End the loop
			break
		}
		if line[i] == `#` {
			ved.add_chunk(.a_comment, start, line.len)
			i = line.len // End the loop
			break
		}

		// Single line Comment (e.g., /* ... */ or <!-- ... -->)
		// Updated to use string-based delimiters.
		if i + mcomment.start.len <= line.len && line[i..i + mcomment.start.len] == mcomment.start {
			end_pos := line.index_after(mcomment.end, i + mcomment.start.len) or { -1 }
			if end_pos != -1 {
				ved.add_chunk(.a_comment, start, end_pos + mcomment.end.len)
				i = end_pos + mcomment.end.len // Move past the comment
				continue
			} else {
				// This case (start found but no end on this line) should be handled by the new logic in draw_split.
				// If we reach here, it means draw_split decided this line doesn't start a *continuing* multiline comment.
				// Treat the start delimiter as normal text by just advancing `i`.
				i += 1
				continue
			}
		}

		// String '...'
		if line[i] == `'` {
			mut end := i + 1
			for end < line.len && line[end] != `'` {
				// Handle escaped quote \'
				if line[end] == `\\` && end + 1 < line.len && line[end + 1] == `'` {
					end++ // Skip escaped quote
				}
				end++
			}
			if end >= line.len {
				end = line.len - 1
			} else {
				end += 1
			} // include closing quote
			ved.add_chunk(.a_string, start, end)
			if i == end {
				i++
			} else {
				i = end // Move past the string
			}
			continue
		}
		// String "..."
		if line[i] == `"` {
			mut end := i + 1
			for end < line.len && line[end] != `"` {
				// Handle escaped quote \"
				if line[end] == `\\` && end + 1 < line.len && line[end + 1] == `"` {
					end++ // Skip escaped quote
				}
				end++
			}
			if end >= line.len {
				end = line.len - 1
			} else {
				end += 1
			} // include closing quote
			ved.add_chunk(.a_string, start, end)
			if i == end {
				i++
			} else {
				i = end // Move past the string
			}
			continue
		}
		// Key
		if is_alpha_underscore(int(line[i])) {
			mut end := i + 1
			for end < line.len && is_alpha_underscore(int(line[end])) {
				end++
			}
			word := line[start..end]
			if word in cur_syntax.literals {
				ved.add_chunk(.a_lit, start, end)
			} else if word in cur_syntax.keywords {
				ved.add_chunk(.a_key, start, end)
			}
			// If it's not a keyword or literal, it will be drawn as normal text later.
			if i == end {
				i++
			} else {
				i = end // Move past the word
			}
			continue
		}

		// If none of the above matched, advance by one character
		i++
	}

	// --- Keep the original chunk drawing logic ---
	if ved.chunks.len == 0 {
		ved.gg.draw_text(x, y, line, ved.cfg.txt_cfg)
		return
	}
	mut pos := 0
	// println('"$line" nr chunks=$ved.chunks.len')
	// TODO use runes
	// runes := msg.runes.slice_fast(chunk.pos, chunk.end)
	// txt := join_strings(runes)
	for j, chunk in ved.chunks {
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
		if j == ved.chunks.len - 1 && chunk.end < line.len {
			final := line[chunk.end..]
			ved.gg.draw_text(x + pos * ved.cfg.char_width, y, final, ved.cfg.txt_cfg)
		}
	}
	// --- End of original chunk drawing logic ---
}
