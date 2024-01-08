module main

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
