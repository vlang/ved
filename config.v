// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gx
import toml

// The different kinds of cursors
enum Cursor {
	block
	beam
	variable
}

// Config structure
// TODO: Load user config from file
struct Config {
mut:
	settings        toml.Doc
	dark_mode       bool
	cursor_style    Cursor
	text_size       int
	line_height     int
	char_width      int
	tab_size        int
	tab             int
	backspace_go_up bool
	vcolor          gx.Color
	split_color     gx.Color
	bgcolor         gx.Color // base00
	errorbgcolor    gx.Color // base08
	title_color     gx.Color // base04
	cursor_color    gx.Color // base05
	string_color    gx.Color // base0B
	string_cfg      gx.TextCfg
	key_color       gx.Color // base0E
	key_cfg         gx.TextCfg
	text_color      gx.Color // base05
	txt_cfg         gx.TextCfg
	comment_color   gx.Color // base03
	comment_cfg     gx.TextCfg
	file_name_color gx.Color
	file_name_cfg   gx.TextCfg
	plus_color      gx.Color
	plus_cfg        gx.TextCfg
	minus_color     gx.Color
	minus_cfg       gx.TextCfg
	line_nr_color   gx.Color // base01
	line_nr_cfg     gx.TextCfg
	green_color     gx.Color // base0B
	green_cfg       gx.TextCfg
	red_color       gx.Color // base08
	red_cfg         gx.TextCfg
}

fn (mut config Config) set_settings(path string) {
	config.settings = toml.parse_file(path) or { toml.parse_text('') or { panic(err) } }
}

fn (mut config Config) reload_config() {
	config.init_colors()

	config.set_cursor_style()
	config.set_text_size()
	config.set_line_height()
	config.set_char_width()
	config.set_tab()
	config.set_backspace_behaviour()
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

fn (mut config Config) init_colors() {
	toml_dark_mode := config.settings.value('editor.dark_mode').bool()
	config.dark_mode = toml_dark_mode || '-dark' in os.args
}

fn (mut config Config) set_cursor_style() {
	toml_cursor_style := config.settings.value('editor.cursor').string()
	if toml_cursor_style != 'toml.Any(toml.Null{})' {
		match toml_cursor_style {
			'block' { config.cursor_style = .block }
			'beam' { config.cursor_style = .beam }
			'variable' { config.cursor_style = .variable }
			else { config.cursor_style = .variable }
		}
		return
	}
	config.cursor_style = .variable
}

fn (mut config Config) set_text_size() {
	toml_text_size := config.settings.value('editor.text_size').int()
	config.text_size = if toml_text_size > 0 { toml_text_size } else { 18 }
}

fn (mut config Config) set_line_height() {
	toml_line_height := config.settings.value('editor.line_height').int()
	config.line_height = if toml_line_height > 0 { toml_line_height } else { 20 }
}

fn (mut config Config) set_char_width() {
	toml_char_width := config.settings.value('editor.char_width').int()
	config.char_width = if toml_char_width > 0 { toml_char_width } else { 8 }
}

fn (mut config Config) set_tab() {
	toml_tab_size := config.settings.value('editor.tab_size').int()
	config.tab_size = if toml_tab_size > 0 { toml_tab_size } else { 4 }

	// TODO: read this in from the config file
	config.tab = int(`\t`)
}

fn (mut config Config) set_backspace_behaviour() {
	toml_backspace_behaviour := config.settings.value('editor.backspace_go_up').bool()
	config.backspace_go_up = toml_backspace_behaviour
}

// Convert a toml key color (in hex) to a gx.Color type
fn (config Config) get_toml_color(base string) !gx.Color {
	toml_hex := config.settings.value('colors.base$base').string()
	if toml_hex != 'toml.Any(toml.Null{})' {
		toml_red := ('0x' + toml_hex[0..2]).u8()
		toml_green := ('0x' + toml_hex[2..4]).u8()
		toml_blue := ('0x' + toml_hex[4..6]).u8()

		return gx.rgb(toml_red, toml_green, toml_blue)
	}

	return error('Couldn\'t read base$base from the settings file')
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

// base 00
fn (mut config Config) set_bgcolor() {
	config.bgcolor = config.get_toml_color('00') or {
		if config.dark_mode {
			gx.rgb(30, 30, 30)
		} else {
			gx.rgb(245, 245, 245)
		}
	}
}

// base 01
fn (mut config Config) set_errorbgcolor() {
	config.errorbgcolor = config.get_toml_color('01') or { gx.rgb(240, 0, 0) }
}

// base 0B
fn (mut config Config) set_string() {
	config.string_color = config.get_toml_color('0B') or { gx.rgb(179, 58, 44) }

	config.string_cfg = gx.TextCfg{
		size: config.text_size
		color: config.string_color
	}
}

// base 0E
fn (mut config Config) set_key() {
	config.key_color = config.get_toml_color('0E') or { gx.rgb(74, 103, 154) }

	config.key_cfg = gx.TextCfg{
		size: config.text_size
		color: config.key_color
	}
}

// base 04
fn (mut config Config) set_title() {
	config.title_color = config.get_toml_color('04') or { gx.rgb(40, 40, 40) }
}

// base 05
fn (mut config Config) set_cursor() {
	config.cursor_color = config.get_toml_color('05') or {
		if !config.dark_mode {
			gx.black
		} else {
			gx.white
		}
	}
}

// base 05 (again)
fn (mut config Config) set_txt() {
	config.text_color = config.get_toml_color('05') or {
		if !config.dark_mode {
			gx.black
		} else {
			gx.rgb(212, 212, 212)
		}
	}

	config.txt_cfg = gx.TextCfg{
		size: config.text_size
		color: config.text_color
	}
}

// base 03
fn (mut config Config) set_comment() {
	config.comment_color = config.get_toml_color('03') or { gx.dark_gray }

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

// base 01
fn (mut config Config) set_line_nr() {
	config.line_nr_color = config.get_toml_color('01') or { gx.dark_gray }

	config.line_nr_cfg = gx.TextCfg{
		size: config.text_size
		color: config.line_nr_color
		align: gx.align_right
	}
}

// base 0B
fn (mut config Config) set_green() {
	config.green_color = config.get_toml_color('0B') or { gx.green }

	config.green_cfg = gx.TextCfg{
		size: config.text_size
		color: config.green_color
	}
}

fn (mut config Config) set_red() {
	config.red_color = config.get_toml_color('08') or { gx.red }
	config.red_cfg = gx.TextCfg{
		size: config.text_size
		color: config.red_color
	}
}
