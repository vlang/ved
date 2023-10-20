// Copyright (c) 2019-2023 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

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
