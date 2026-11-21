module main

// Regression tests for #101 (`gd` substr panic in `word_under_cursor`)
// and #172 (crash on `dd` with cursor past end of buffer).

fn test_dd_on_empty_buffer_does_nothing() {
	mut ved := &Ved{}
	mut view := ved.new_view()
	view.lines = []
	view.y = 0
	view.dd()
	assert view.lines == []
}

fn test_dd_past_end_of_buffer_does_nothing() {
	mut ved := &Ved{}
	mut view := ved.new_view()
	view.lines = ['a', 'b']
	view.y = 2
	view.dd()
	assert view.lines == ['a', 'b']
}

fn test_dd_negative_y_does_nothing() {
	mut ved := &Ved{}
	mut view := ved.new_view()
	view.lines = ['a', 'b']
	view.y = -1
	view.dd()
	assert view.lines == ['a', 'b']
}

fn test_dd_deletes_current_line() {
	mut ved := &Ved{}
	mut view := ved.new_view()
	view.lines = ['a', 'b', 'c']
	view.y = 1
	view.dd()
	assert view.lines == ['a', 'c']
	assert ved.ylines == ['b']
}

fn test_word_under_cursor_inside_word() {
	mut ved := &Ved{}
	mut vw := ved.new_view()
	ved.view = &vw
	ved.view.lines = ['hello world']
	ved.view.y = 0
	ved.view.x = 7
	assert ved.word_under_cursor() == 'world'
}

fn test_word_under_cursor_past_eol() {
	mut ved := &Ved{}
	mut vw := ved.new_view()
	ved.view = &vw
	ved.view.lines = ['hello world']
	ved.view.y = 0
	// Cursor one past the end maps to the last word instead of panicking.
	ved.view.x = 11
	assert ved.word_under_cursor() == 'world'
	// Far out of range returns '' instead of panicking.
	ved.view.x = 100
	assert ved.word_under_cursor() == ''
}

fn test_word_under_cursor_empty_line() {
	mut ved := &Ved{}
	mut vw := ved.new_view()
	ved.view = &vw
	ved.view.lines = ['']
	ved.view.y = 0
	ved.view.x = 0
	assert ved.word_under_cursor() == ''
	ved.view.x = 1
	assert ved.word_under_cursor() == ''
}

fn test_word_under_cursor_no_right_bounds() {
	mut ved := &Ved{}
	mut vw := ved.new_view()
	ved.view = &vw
	ved.view.lines = ['  hello']
	ved.view.y = 0
	ved.view.x = 0
	assert ved.word_under_cursor_no_right() == ''
	ved.view.x = 7
	assert ved.word_under_cursor_no_right() == 'hello'
	ved.view.x = 100
	assert ved.word_under_cursor_no_right() == ''
}
