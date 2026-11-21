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

// lex_standard_span scans a single line without multi-line comment state
// and returns its highlight chunks. Pure function: no drawing, no globals.
// Extracted unchanged from draw_text_line_standard_syntax.
fn lex_standard_span(line string, mcomment Mcomment, keywords map[string]bool, literals map[string]bool) []Chunk {
	mut chunks := []Chunk{}
	// TODO use runes for everything to fix keyword + 2+ byte rune words

	mut i := 0 // Use mut i instead of for loop index to allow manual increment
	for i < line.len {
		start := i
		// Comment // #
		if i > 0 && line[i - 1] == `/` && line[i] == `/` {
			chunks << Chunk{
				start: start - 1
				end:   line.len
				typ:   .a_comment
			}
			i = line.len // End the loop
			break
		}
		if line[i] == `#` {
			chunks << Chunk{
				start: start
				end:   line.len
				typ:   .a_comment
			}
			i = line.len // End the loop
			break
		}

		// Single line Comment (e.g., /* ... */ or <!-- ... -->)
		// Updated to use string-based delimiters.
		if i + mcomment.start.len <= line.len && line[i..i + mcomment.start.len] == mcomment.start {
			end_pos := line.index_after(mcomment.end, i + mcomment.start.len) or { -1 }
			if end_pos != -1 {
				chunks << Chunk{
					start: start
					end:   end_pos + mcomment.end.len
					typ:   .a_comment
				}
				i = end_pos + mcomment.end.len // Move past the comment
				continue
			} else {
				// Start found but no end on this line; the caller (lex_line)
				// decides whether this opens a continuing multiline comment.
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
			chunks << Chunk{
				start: start
				end:   end
				typ:   .a_string
			}
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
			chunks << Chunk{
				start: start
				end:   end
				typ:   .a_string
			}
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
			if word in literals {
				chunks << Chunk{
					start: start
					end:   end
					typ:   .a_lit
				}
			} else if word in keywords {
				chunks << Chunk{
					start: start
					end:   end
					typ:   .a_key
				}
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
	return chunks
}

// lex_line highlights one display line given the multi-line comment state
// at its start. Returns the chunks and the state for the next line.
// Pure function: extracted from draw_split, output identical to it.
fn lex_line(s string, ml_before bool, ext string, keywords map[string]bool, literals map[string]bool) ([]Chunk, bool) {
	mcomment := get_mcomment_by_ext(ext)
	mut chunks := []Chunk{}
	mut ml := ml_before
	// Handle multi page /**/
	// Find the position of start and end comment delimiters on the current line.
	// This now uses the string-based delimiters from the Mcomment struct.
	start_comment_pos := s.index(mcomment.start) or { -1 }
	end_comment_pos := s.index(mcomment.end) or { -1 }

	// This logic handles rendering for a line that starts inside a multi-line comment.
	if ml {
		if end_comment_pos != -1 { // The multi-line comment ends on this line.
			// The part of the line that is inside the comment.
			// The slice now uses `mcomment.end.len` for an accurate length.
			chunks << Chunk{
				start: 0
				end:   end_comment_pos + mcomment.end.len
				typ:   .a_comment
			}

			// The rest of the line (after the comment) uses standard syntax highlighting.
			rest_off := end_comment_pos + mcomment.end.len
			normal_part := s[rest_off..]
			if normal_part.len > 0 {
				for c in lex_standard_span(normal_part, mcomment, keywords, literals) {
					chunks << Chunk{
						start: c.start + rest_off
						end:   c.end + rest_off
						typ:   c.typ
					}
				}
			}

			// The comment block is now closed.
			ml = false
		} else { // The entire line is still inside the comment.
			chunks << Chunk{
				start: 0
				end:   s.len
				typ:   .a_comment
			}
			// `ml` remains true for the next line.
		}
	} else { // ml is false
		if start_comment_pos != -1
			&& (end_comment_pos == -1 || end_comment_pos < start_comment_pos) { // Comment starts here and continues
			// Normal part before / *
			for c in lex_standard_span(s[..start_comment_pos], mcomment, keywords, literals) {
				chunks << c
			}
			// Comment part from / * onwards
			chunks << Chunk{
				start: start_comment_pos
				end:   s.len
				typ:   .a_comment
			}
			ml = true // Update state for next line
		} else { // No multiline comment start OR it's a single-line /* ... */
			// Use the standard highlighter for the whole line
			chunks = lex_standard_span(s, mcomment, keywords, literals)
			// ml remains false
		}
	}
	return chunks, ml
}

// draw_chunks replays lexed chunks to the screen. Extracted unchanged
// from draw_text_line_standard_syntax.
fn (mut ved Ved) draw_chunks(x int, y int, line string, chunks []Chunk) {
	if chunks.len == 0 {
		ved.gg.draw_text(x, y, line, ved.cfg.txt_cfg)
		return
	}
	mut pos := 0
	// println('"$line" nr chunks=$chunks.len')
	// TODO use runes
	// runes := msg.runes.slice_fast(chunk.pos, chunk.end)
	// txt := join_strings(runes)
	for j, chunk in chunks {
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
		if j == chunks.len - 1 && chunk.end < line.len {
			final := line[chunk.end..]
			ved.gg.draw_text(x + pos * ved.cfg.char_width, y, final, ved.cfg.txt_cfg)
		}
	}
}
