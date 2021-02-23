// Copyright (c) 2019-2021 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import time
import gg
import gx
import os

const (
	time_cfg = gx.TextCfg{
		color: gx.gray
		size: 14
	}
)

const (
	color_distracting = gx.rgb(255, 111, 130)
	color_productive  = gx.rgb(50, 90, 110) // gx.rgb(167,236,82)
	color_neutral     = gx.rgb(39, 195, 221)
)

struct Timer {
mut:
	gg    &gg.Context
	tasks []Task
	date  time.Time
}

struct Task {
	start        int
	end          int
	name         string
	color        gx.Color
	duration     string
	duration_min int
	productive   bool
}

fn (mut t Timer) load_tasks() {
	// println('timer.load_tasks()')
	lines := os.read_lines(tasks_path) or { return }
	// println(lines)
	mut tasks := []Task{}
	today := t.date.ymmdd()
	// println('day=$today')
	for line in lines {
		// println(line)
		if !line.contains('|') {
			continue
		}
		if !line.contains(today) {
			continue
		}
		words_ := line.split('|')
		words := words_.filter(it != '')
		// println('wordss:')
		// println(words)
		if words.len != 4 {
			continue
		}
		time := words[2].trim_space()
		// println('time=$time')
		a := time.split(' ')
		// println('a=') println(a)
		if a.len < 2 {
			continue
		}
		b := a[1].split(':')
		// println('b=') println(b)
		if b.len < 2 {
			continue
		}
		hour := b[0].int()
		min := b[1].int()
		end_time := words[3]
		hhmm := end_time.split(':')
		hour_end := hhmm[0].trim_space().int()
		min_end := hhmm[1].trim_space().int()
		name := words[0].trim_space()
		duration := words[1].trim_space()
		productive := !name.starts_with('@')
		color := if productive { color_productive } else { color_distracting }
		// TODO autofree bug remove clone()
		name2 := if productive { name.clone() } else { name[1..] }
		task := Task{
			start: hour * 60 + min
			end: hour_end * 60 + min_end
			name: name2
			duration: duration
			duration_min: duration[..duration.len - 1].int()
			color: color
			productive: productive
		}
		// println('task:')
		// println(task)
		if task.end < task.start {
			continue
		}
		tasks << task
	}
	// println('tasks.len=$tasks.len')
	t.tasks = tasks
}

fn new_timer(gg &gg.Context) Timer {
	mut timer := Timer{
		gg: gg
		date: time.now()
	}
	timer.load_tasks()
	return timer
}

// fn (mut t Timer) load_tasks() {
// }
fn (mut t Timer) draw() {
	window_width := t.gg.width / 2
	window_height := t.gg.height - 20
	window_x := (t.gg.width - window_width) / 2
	window_y := (t.gg.height - window_height) / 2
	t.gg.draw_rect(window_x, window_y, window_width, window_height, gx.white)
	hour_width := window_height / 24 // window_width / 25// 60 / scale  // 60 min
	scale := 60.0 / f64(hour_width)
	mut total := 0
	for task in t.tasks {
		// println('TASK $task')
		if task.duration.len < 3 {
			continue
		}
		x := f64(window_x) + 30.0
		y := f64(window_y) + f64(task.start) / scale + 10
		height := f64(task.end - task.start) / scale
		t.gg.draw_rect(f32(x), f32(y), f32(hour_width), f32(height), task.color)
		t.gg.draw_text(int(x) + hour_width + 10, int(y) + 5, task.name + ' ' + task.duration,
			gx.TextCfg{
			color: task.color
		})
		if task.productive {
			total += task.duration_min
		}
	}
	for hour in 0 .. 24 + 1 {
		hour_y := window_y + hour * hour_width + 10
		hour_x := window_x + 30
		if hour < 24 {
			t.gg.draw_text(hour_x - 25, hour_y + 10, '${hour:02d}', time_cfg)
		}
		t.gg.draw_line(hour_x, hour_y, hour_x + hour_width, hour_y, gx.gray)
	}
	// Large left vertical line
	t.gg.draw_line(window_x + 30, window_y + 10, window_x + 30, window_y + 10 + 24 * hour_width,
		gx.gray)
	// Large right vertical line
	t.gg.draw_line(window_x + 30 + hour_width, window_y + 10, window_x + 30 + hour_width,
		window_y + 10 + 24 * hour_width, gx.gray)
	// Draw the date in the top right corner
	t.gg.draw_text_def(window_x + window_width - 100, 20, t.date.ymmdd())
	// Draw total time
	h := total / 60
	m := total % 60
	t.gg.draw_text(window_x + window_width - 100, 100, '$h:${m:02d}', gx.TextCfg{
		color: color_productive
	})
}

fn (mut timer Timer) key_down(key gg.KeyCode, super bool) {
	match key {
		.up, .k {
			timer.date = timer.date.add_days(-1)
			timer.load_tasks()
		}
		.down, .j {
			timer.date = timer.date.add_days(1)
			timer.load_tasks()
		}
		else {}
	}
}
