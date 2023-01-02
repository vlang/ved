// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import json

struct Syntax {
	name       string
	extensions []string
	fmt_cmd    string
	keywords   []string
	literals   []string
}

fn (mut ved Ved) load_syntaxes() {
	println('loading syntax files...')
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
		ved.syntaxes << syntax
	}
	println('${files.len} syntax files loaded')
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
