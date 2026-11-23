module main

// Regression test for the visual-selection viewport cull in draw.v.
//
// draw_split() renders text line j at y = (j - from + 1) * line_height.
// The .visual loop highlights line j with yy = j + 1 (vstart/vend + 1), while
// .visual_block uses yy = j. The cull must keep exactly the visible lines
// [from, from + page_height) for both loops.

const cull_from = 100

const cull_page_height = 49

fn test_visual_selection_keeps_last_visible_line() {
	last_visible_line := cull_from + cull_page_height - 1
	yy := last_visible_line + 1 // .visual stores vstart/vend + 1
	assert visual_row_in_viewport(yy, cull_from, cull_page_height, 1), '.visual culls yy=${yy}: the highlight for the last visible text line ${last_visible_line} disappears'
}

fn test_visual_selection_drops_rows_outside_viewport() {
	// yy == from maps to text line from-1, above the viewport (covered by the title bar).
	assert !visual_row_in_viewport(cull_from, cull_from, cull_page_height, 1)
	// yy == from + page_height + 1 maps to text line from + page_height, below the viewport.
	assert !visual_row_in_viewport(cull_from + cull_page_height + 1, cull_from, cull_page_height, 1)
}

fn test_visual_block_cull_matches_visible_lines() {
	assert visual_row_in_viewport(cull_from, cull_from, cull_page_height, 0)
	assert visual_row_in_viewport(cull_from + cull_page_height - 1, cull_from, cull_page_height, 0)
	assert !visual_row_in_viewport(cull_from + cull_page_height, cull_from, cull_page_height, 0)
}
