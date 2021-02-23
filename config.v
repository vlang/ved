// Copyright (c) 2019-2021 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gx

// Config structure
// TODO: Load user config from file
struct Config {
mut:
	dark_mode       bool
	text_size       int
	tab_size        int
	tab             int
	backspace_go_up bool
	vcolor          gx.Color
	split_color     gx.Color
	bgcolor         gx.Color
	errorbgcolor    gx.Color
	title_color     gx.Color
	cursor_color    gx.Color
	string_color    gx.Color
	string_cfg      gx.TextCfg
	key_color       gx.Color
	key_cfg         gx.TextCfg
	text_color      gx.Color
	txt_cfg         gx.TextCfg
	comment_color   gx.Color
	comment_cfg     gx.TextCfg
	file_name_color gx.Color
	file_name_cfg   gx.TextCfg
	plus_color      gx.Color
	plus_cfg        gx.TextCfg
	minus_color     gx.Color
	minus_cfg       gx.TextCfg
	line_nr_color   gx.Color
	line_nr_cfg     gx.TextCfg
	green_color     gx.Color
	green_cfg       gx.TextCfg
	red_color       gx.Color
	red_cfg         gx.TextCfg
}

fn (mut config Config) init_colors() {
	config.dark_mode = '-dark' in os.args
	config.reload_config()
}

fn (mut config Config) reload_config() {
	config.set_textsize()
	config.set_tab()
	config.set_vcolor()
	config.set_split()
	config.set_bgcolor()
	config.set_errorbgcolor()
	config.set_string()
	config.set_key()
	config.set_title()
	config.set_cursor()
	config.set_txt()
	config.set_comment()
	config.set_filename()
	config.set_plus()
	config.set_minus()
	config.set_line_nr()
	config.set_green()
	config.set_red()
}

fn (mut config Config) set_textsize() {
	config.text_size = 18
}

fn (mut config Config) set_tab() {
	config.tab_size = 4
	config.tab = int(`\t`)
}

fn (mut config Config) set_vcolor() {
	if !config.dark_mode {
		config.vcolor = gx.rgb(226, 233, 241)
	} else {
		config.vcolor = gx.rgb(60, 60, 60)
	}
}

fn (mut config Config) set_split() {
	if !config.dark_mode {
		config.split_color = gx.rgb(223, 223, 223)
	} else {
		config.split_color = gx.rgb(50, 50, 50)
	}
}

fn (mut config Config) set_bgcolor() {
	if !config.dark_mode {
		config.bgcolor = gx.rgb(245, 245, 245)
	} else {
		config.bgcolor = gx.rgb(30, 30, 30)
	}
}

fn (mut config Config) set_errorbgcolor() {
	if !config.dark_mode {
		config.errorbgcolor = gx.rgb(240, 0, 0)
	} else {
		config.errorbgcolor = gx.rgb(240, 0, 0)
	}
}

fn (mut config Config) set_string() {
	if !config.dark_mode {
		config.string_color = gx.rgb(179, 58, 44)
	} else {
		config.string_color = gx.rgb(179, 58, 44)
	}
	config.string_cfg = gx.TextCfg{
		size: config.text_size
		color: config.string_color
	}
}

fn (mut config Config) set_key() {
	if !config.dark_mode {
		config.key_color = gx.rgb(74, 103, 154)
	} else {
		config.key_color = gx.rgb(74, 103, 154)
	}
	config.key_cfg = gx.TextCfg{
		size: config.text_size
		color: config.key_color
	}
}

fn (mut config Config) set_title() {
	if !config.dark_mode {
		config.title_color = gx.rgb(40, 40, 40)
	} else {
		config.title_color = gx.rgb(40, 40, 40)
	}
}

fn (mut config Config) set_cursor() {
	if !config.dark_mode {
		config.cursor_color = gx.black
	} else {
		config.cursor_color = gx.white
	}
}

fn (mut config Config) set_txt() {
	if !config.dark_mode {
		config.text_color = gx.black
	} else {
		config.text_color = gx.rgb(212, 212, 212)
	}
	config.txt_cfg = gx.TextCfg{
		size: config.text_size
		color: config.text_color
	}
}

fn (mut config Config) set_comment() {
	config.comment_color = gx.dark_gray
	config.comment_cfg = gx.TextCfg{
		size: config.text_size
		color: config.comment_color
	}
}

fn (mut config Config) set_filename() {
	config.file_name_color = gx.white
	config.file_name_cfg = gx.TextCfg{
		size: config.text_size
		color: config.file_name_color
	}
}

fn (mut config Config) set_plus() {
	config.plus_color = gx.green
	config.plus_cfg = gx.TextCfg{
		size: config.text_size
		color: config.plus_color
	}
}

fn (mut config Config) set_minus() {
	config.minus_color = gx.green
	config.minus_cfg = gx.TextCfg{
		size: config.text_size
		color: config.minus_color
	}
}

fn (mut config Config) set_line_nr() {
	config.line_nr_color = gx.dark_gray
	config.line_nr_cfg = gx.TextCfg{
		size: config.text_size
		color: config.line_nr_color
		align: gx.align_right
	}
}

fn (mut config Config) set_green() {
	config.green_color = gx.green
	config.green_cfg = gx.TextCfg{
		size: config.text_size
		color: config.green_color
	}
}

fn (mut config Config) set_red() {
	config.red_color = gx.red
	config.red_cfg = gx.TextCfg{
		size: config.text_size
		color: config.red_color
	}
}
