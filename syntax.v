// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import x.json2

const builtin_v_syntax_file_content = $embed_file('syntax/v.syntax').to_string()

struct Syntax {
	name       string
	extensions []string
	fmt_cmd    string
	keywords   []string
	literals   []string
mut:
	keywords_map map[string]bool
	literals_map map[string]bool
}

// build_syntax_index precomputes keyword/literal lookup maps so the
// per-frame highlighter does hash lookups instead of linear scans.
fn build_syntax_index(mut syntax Syntax) {
	syntax.keywords_map = {}
	for k in syntax.keywords {
		syntax.keywords_map[k] = true
	}
	syntax.literals_map = {}
	for l in syntax.literals {
		syntax.literals_map[l] = true
	}
}

fn (mut ved Ved) load_syntaxes() {
	println('loading syntax files...')
	mut vsyntax := json2.decode[Syntax](builtin_v_syntax_file_content) or {
		panic('the builtin syntax file "${builtin_v_syntax_file_content}" can not be decoded ${err}')
	}
	build_syntax_index(mut vsyntax)
	ved.syntaxes << vsyntax
	files := os.walk_ext(syntax_dir, '.syntax')
	for file in files {
		fcontent := os.read_file(file) or {
			eprintln('    error: cannot load syntax file ${file}: ${err.msg()}')
			'{}'
		}
		mut syntax := json2.decode[Syntax](fcontent) or {
			eprintln('    error: cannot load syntax file ${file}: ${err.msg()}')
			Syntax{}
		}
		build_syntax_index(mut syntax)
		if file.ends_with('v.syntax') {
			// allow overriding the builtin embedded syntax at runtime:
			ved.syntaxes[0] = syntax
			continue
		}
		ved.syntaxes << syntax
	}
	println('${files.len} syntax files loaded + the compile time builtin syntax for .v')
}

fn (mut ved Ved) set_current_syntax_idx(ext string) {
	for i, syntax in ved.syntaxes {
		if ext in syntax.extensions {
			println('selected syntax ${syntax.name} for extension ${ext}')
			ved.current_syntax_idx = i
			break
		}
	}
}
