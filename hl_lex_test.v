module main

// Tests for the pure highlight lexer (lex_standard_span, lex_line).
// These lock the pre-existing rendering behavior so the per-line cache
// follow-up can rely on identical output.

fn test_syntax_index() {
	mut s := Syntax{
		keywords: ['fn', 'return']
		literals: ['true']
	}
	build_syntax_index(mut s)
	assert 'fn' in s.keywords_map
	assert 'return' in s.keywords_map
	assert 'nope' !in s.keywords_map
	assert 'true' in s.literals_map
}

fn test_mcomment_by_ext() {
	assert get_mcomment_by_ext('.v') == Mcomment{
		start: '/*'
		end:   '*/'
	}
	assert get_mcomment_by_ext('.html') == Mcomment{
		start: '<!--'
		end:   '-->'
	}
}

fn test_lex_keyword() {
	mc := get_mcomment_by_ext('.v')
	kw := {
		'fn':     true
		'return': true
	}
	lit := map[string]bool{}
	chunks := lex_standard_span('fn main()', mc, kw, lit)
	assert chunks == [Chunk{
		start: 0
		end:   2
		typ:   .a_key
	}]
}

fn test_lex_plain_text_has_no_chunks() {
	mc := get_mcomment_by_ext('.v')
	kw := {
		'fn': true
	}
	lit := map[string]bool{}
	assert lex_standard_span('hello = 1', mc, kw, lit) == []
	assert lex_standard_span('', mc, kw, lit) == []
}

fn test_lex_string_and_line_comment() {
	mc := get_mcomment_by_ext('.v')
	kw := map[string]bool{}
	lit := map[string]bool{}
	chunks := lex_standard_span("x = 'hi' // done", mc, kw, lit)
	assert chunks == [Chunk{
		start: 4
		end:   8
		typ:   .a_string
	}, Chunk{
		start: 9
		end:   16
		typ:   .a_comment
	}]
}

fn test_lex_single_line_block_comment() {
	mc := get_mcomment_by_ext('.v')
	kw := {
		'fn': true
	}
	lit := map[string]bool{}
	chunks := lex_standard_span('/* bold */ plain', mc, kw, lit)
	assert chunks == [Chunk{
		start: 0
		end:   10
		typ:   .a_comment
	}]
}

fn test_lex_hash_comment() {
	mc := get_mcomment_by_ext('.v')
	kw := map[string]bool{}
	lit := map[string]bool{}
	chunks := lex_standard_span('# header', mc, kw, lit)
	assert chunks == [Chunk{
		start: 0
		end:   8
		typ:   .a_comment
	}]
}

fn test_lex_line_opens_multiline_comment() {
	mc_kw := {
		'fn': true
	}
	lit := map[string]bool{}
	chunks, ml := lex_line('int x; /* open', false, '.v', mc_kw, lit)
	assert ml == true
	assert chunks == [Chunk{
		start: 7
		end:   14
		typ:   .a_comment
	}]
}

fn test_lex_line_closes_multiline_comment() {
	kw := map[string]bool{}
	lit := map[string]bool{}
	chunks, ml := lex_line('still comment */ tail', true, '.v', kw, lit)
	assert ml == false
	assert chunks == [Chunk{
		start: 0
		end:   16
		typ:   .a_comment
	}]
}

fn test_lex_line_balanced_comment_stays_shut() {
	kw := {
		'fn': true
	}
	lit := map[string]bool{}
	chunks, ml := lex_line('/* a */ b /* c', false, '.v', kw, lit)
	assert ml == false
	assert chunks == [Chunk{
		start: 0
		end:   7
		typ:   .a_comment
	}]
}
