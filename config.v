// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gx
// import toml
import json

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
	// settings        toml.Doc
	dark_mode       bool
	cursor_style    Cursor
	text_size       int = min_text_size
	line_height     int = 20
	char_width      int = 8
	tab_size        int = 4
	tab             int = int(`\t`) // TODO read from config file?
	backspace_go_up bool
	vcolor          gx.Color // v selection background color
	split_color     gx.Color
	bgcolor         gx.Color // base00
	errorbgcolor    gx.Color // base08
	title_color     gx.Color // base04
	cursor_color    gx.Color // base05
	string_color    gx.Color // base0B
	string_cfg      gx.TextCfg
	key_color       gx.Color // base0E
	key_cfg         gx.TextCfg
	lit_color       gx.Color // base0E
	lit_cfg         gx.TextCfg
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
	disable_mouse   bool = true
	show_file_tree  bool
	// Config.json
	disable_fmt bool
}

/*
// json
struct Config2 {
	disable_fmt bool
	text_size   int
	line_height int
	char_width  int
}
*/

/*
fn (mut config Config) set_settings(path string) {
	config.settings = toml.parse_file(path) or { toml.parse_text('') or { panic(err) } }
}
*/

// reload_config reloads the config from config.toml file
// set_default_color_values?
fn (mut config Config) set_default_values() {
	config.init_colors()

	config.set_cursor_style()
	// config.set_text_size()
	// config.set_line_height()
	// config.set_char_width()
	// config.set_tab()
	// config.set_backspace_behaviour()
	// config.set_disable_mouse()
	config.set_vcolor()
	config.set_split()
	config.set_bgcolor()
	config.set_errorbgcolor()
	config.set_string()
	config.set_key()
	config.set_lit()
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
	config.dark_mode ||= '-dark' in os.args
}

fn (mut config Config) set_cursor_style() {
	/*
	toml_cursor_style := config.settings.value('editor.cursor').string()
	if toml_cursor_style != 'toml.Any(toml.Null{})' {
		match toml_cursor_style {
			'block' { config.cursor_style = .block }
			'beam' { config.cursor_style = .beam }
			'variable' { config.cursor_style = .variable }
			else { config.cursor_style = .block }
		}
		return
	}
	*/
	config.cursor_style = .block
}

// Convert a toml key color (in hex) to a gx.Color type
/*
fn (config Config) get_toml_color(base string) !gx.Color {

	toml_hex := config.settings.value('colors.base${base}').string()
	if toml_hex != 'toml.Any(toml.Null{})' {
		toml_red := ('0x' + toml_hex[0..2]).u8()
		toml_green := ('0x' + toml_hex[2..4]).u8()
		toml_blue := ('0x' + toml_hex[4..6]).u8()

		return gx.rgb(toml_red, toml_green, toml_blue)
	}

	return error('Couldn\'t read base${base} from the settings file')
}
*/

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
	// config.bgcolor = config.get_toml_color('00') or {
	config.bgcolor = if config.dark_mode {
		gx.rgb(30, 30, 30)
	} else {
		gx.rgb(245, 245, 245)
	}
	//}
}

// base 01
fn (mut config Config) set_errorbgcolor() {
	// config.errorbgcolor = config.get_toml_color('01') or { gx.rgb(240, 0, 0) }
	config.errorbgcolor = gx.rgb(240, 0, 0)
}

// base 0B
fn (mut config Config) set_string() {
	// config.string_color = config.get_toml_color('0B') or { gx.rgb(179, 58, 44) }
	config.string_color = gx.rgb(179, 58, 44)
	config.string_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.string_color
	}
}

// base 0E
fn (mut config Config) set_key() {
	// config.key_color = config.get_toml_color('0E') or { gx.rgb(74, 103, 154) }
	config.key_color = gx.rgb(74, 103, 154)

	config.key_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.key_color
	}
}

// base 0F
fn (mut config Config) set_lit() {
	// config.lit_color = config.get_toml_color('0F') or { gx.rgb(7, 103, 154) }
	config.lit_color = gx.rgb(7, 103, 154)

	config.lit_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.lit_color
	}
}

// base 04
fn (mut config Config) set_title() {
	// config.title_color = config.get_toml_color('04') or { gx.rgb(40, 40, 40) }
	config.title_color = gx.rgb(0, 0, 0)
}

// base 05
fn (mut config Config) set_cursor() {
	// config.cursor_color = config.get_toml_color('05') or {
	config.cursor_color = if !config.dark_mode {
		gx.black
	} else {
		gx.white
	}
	//}
}

// base 05 (again)
fn (mut config Config) set_txt() {
	// config.text_color = config.get_toml_color('05') or {
	config.text_color = if !config.dark_mode {
		gx.black
	} else {
		gx.rgb(212, 212, 212)
	}

	config.txt_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.text_color
	}
}

// base 03
fn (mut config Config) set_comment() {
	// config.comment_color = config.get_toml_color('03') or { gx.dark_gray }
	config.comment_color = gx.dark_gray

	config.comment_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.comment_color
	}
}

fn (mut config Config) set_filename() {
	config.file_name_color = gx.white
	config.file_name_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.file_name_color
	}
}

fn (mut config Config) set_plus() {
	config.plus_color = gx.green
	config.plus_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.plus_color
	}
}

fn (mut config Config) set_minus() {
	config.minus_color = gx.green
	config.minus_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.minus_color
	}
}

// base 01
fn (mut config Config) set_line_nr() {
	// config.line_nr_color = config.get_toml_color('01') or { gx.dark_gray }
	config.line_nr_color = gx.dark_gray

	config.line_nr_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.line_nr_color
		align: gx.align_right
	}
}

// base 0B
fn (mut config Config) set_green() {
	// config.green_color = config.get_toml_color('0B') or { gx.green }
	config.green_color = gx.green

	config.green_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.green_color
	}
}

fn (mut config Config) set_red() {
	// config.red_color = config.get_toml_color('08') or { gx.red }
	config.red_color = gx.red
	config.red_cfg = gx.TextCfg{
		size:  config.text_size
		color: config.red_color
	}
}

fn (mut ved Ved) load_config2() {
	if os.exists(config_path2) {
		if conf2 := json.decode(Config, os.read_file(config_path2) or { return }) {
			println('AXAXAXAXA ${conf2}')
			ved.cfg = conf2
			/*
			ved.cfg.disable_fmt = conf2.disable_fmt
			ved.cfg.text_size = conf2.text_size
			ved.cfg.line_height = conf2.line_height
			ved.cfg.char_width = conf2.char_width
			*/
			// ved.cfg.disable_fmt = conf2.disable_fmt
		} else {
			println(err)
		}
	}
	ved.cfg.set_default_values()
}

fn (mut ved Ved) save_config2() {
	/*
	config2 := Config2{
		text_size:   ved.cfg.text_size
		disable_fmt: ved.cfg.disable_fmt
		line_height: ved.cfg.line_height
		char_width:  ved.cfg.char_width
	}
	*/
	os.write_file(config_path2, json.encode_pretty(ved.cfg)) or { panic(err) }
}
