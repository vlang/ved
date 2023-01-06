// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import json

const builtin_v_syntax_file_content = $embed_file('syntax/v.syntax').to_string()

struct Syntax {
	name       string
	extensions []string
	fmt_cmd    string
	keywords   []string
	literals   []string
}

fn (mut ved Ved) load_syntaxes() {
	println('loading syntax files...')
	vsyntax := json.decode(Syntax, builtin_v_syntax_file_content) or {
		panic('the builtin syntax file can not be decoded')
	}
	ved.syntaxes << vsyntax
	files := os.walk_ext(syntax_dir, '.syntax')
	for file in files {
		fcontent := os.read_file(file) or {
			eprintln('    error: cannot load syntax file ${file}: ${err.msg()}')
			'{}'
		}
		syntax := json.decode(Syntax, fcontent) or {
			eprintln('    error: cannot load syntax file ${file}: ${err.msg()}')
			Syntax{}
		}
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
