// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import time

struct Funny {
mut:
	total_width	int
}

fn (mut funny Funny) width_of_text(text string, char_width int) int {
    funny.total_width = text.len * char_width
    return funny.total_width
}

fn nr_spaces_and_tabs_in_line(line string) (int, int) {
	mut nr_spaces := 0
	mut nr_tabs := 0
	mut i := 0

	for i < line.len && (line[i] == ` ` || line[i] == `\t`) {
		if line[i] == ` ` {
			nr_spaces++
		}

		if line[i] == `\t` {
			nr_tabs++
		}

		i++
	}

	return nr_spaces, nr_tabs
}

fn time_format(include_seconds bool, now time.Time) string {
	if include_seconds {
		return now.hhmmss()
	}
	else {
		return now.hhmm()
	}
}