// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gg
import toml
import x.json2

// The different kinds of cursors
enum Cursor {
	block
	beam
	variable
}

// Config structure
struct Config {
mut:
	settings        toml.Doc
	dark_mode       bool
	cursor_style    Cursor
	text_size       int = min_text_size
	line_height     int = 20
	char_width      int = 8
	tab_size        int = 4
	tab             int = int(`\t`) // TODO read from config file?
	backspace_go_up bool
	vcolor          gg.Color // v selection background color
	split_color     gg.Color
	bgcolor         gg.Color // base00
	errorbgcolor    gg.Color // base08
	title_color     gg.Color // base04
	cursor_color    gg.Color // base05
	string_color    gg.Color // base0B
	string_cfg      gg.TextCfg
	key_color       gg.Color // base0E
	key_cfg         gg.TextCfg
	lit_color       gg.Color // base0F
	lit_cfg         gg.TextCfg
	text_color      gg.Color // base05
	txt_cfg         gg.TextCfg
	comment_color   gg.Color // base03
	comment_cfg     gg.TextCfg
	file_name_color gg.Color
	file_name_cfg   gg.TextCfg
	plus_color      gg.Color
	plus_cfg        gg.TextCfg
	minus_color     gg.Color
	minus_cfg       gg.TextCfg
	line_nr_color   gg.Color // base01
	line_nr_cfg     gg.TextCfg
	green_color     gg.Color // base0B
	green_cfg       gg.TextCfg
	red_color       gg.Color // base08
	red_cfg         gg.TextCfg
	disable_mouse   bool = true
	show_file_tree  bool
	// Config.json
	disable_fmt bool
}

// Config2 is the JSON persisted *session* state: settings the user adjusts
// live at runtime (e.g. Cmd +/- to resize text) rather than declares once in
// conf.toml. It intentionally only covers those fields.
struct Config2 {
	disable_fmt bool
	text_size   int
	line_height int
	char_width  int
}

// default_conf_toml mirrors ved's actual hardcoded defaults, so writing it
// out on first run is a noop behaviour wise. The [colors] table ships
// commented out (using the README's example base16 theme as a reference):
// colors.baseXX overrides apply regardless of dark_mode, so prepopulating
// it live would pin colors to one value and defeat the light/dark toggle.
const default_conf_toml = '# Ved configuration file. See the README\'s Configuration section for details.
[editor]
dark_mode = false
cursor = \'block\'        # \'block\', \'beam\' or \'variable\'
text_size = 18
line_height = 20
char_width = 8
tab_size = 4
backspace_go_up = false

# Uncomment (and tweak) to override colors. Ved uses a form of base16;
# this table applies regardless of dark_mode, so if you enable it you\'re
# opting out of the light/dark colour toggle above.
# [colors]
# base00 = "efecf4"
# base01 = "e2dfe7"
# base02 = "8b8792"
# base03 = "7e7887"
# base04 = "655f6d"
# base05 = "585260"
# base06 = "26232a"
# base07 = "19171c"
# base08 = "be4678"
# base09 = "aa573c"
# base0A = "a06e3b"
# base0B = "2a9292"
# base0C = "398bc6"
# base0D = "576ddb"
# base0E = "955ae7"
# base0F = "bf40bf"
'

fn (mut config Config) set_settings(path string) {
	if !os.exists(path) {
		os.write_file(path, default_conf_toml) or { eprintln('could not create ${path}: ${err}') }
	}
	config.settings = toml.parse_file(path) or {
		eprintln('could not parse ${path}: ${err}')
		toml.parse_text('') or { panic(err) }
	}
}

// reload_config reloads the config from config.toml file
// set_default_values applies conf.toml (or hardcoded fallbacks) for
// everything except the live session fields covered by Config2 which the
// caller applies via set_text_metrics.
fn (mut config Config) set_default_values(session Config2) {
	config.set_settings(config_path)
	config.init_colors()

	config.set_cursor_style()
	config.set_tab_size()
	config.set_backspace_behaviour()
	config.set_text_metrics(session)
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
	config.dark_mode ||= '-dark' in os.args || config.settings.value('editor.dark_mode').bool()
}

fn (mut config Config) set_cursor_style() {
	match config.settings.value('editor.cursor').string() {
		'block' { config.cursor_style = .block }
		'beam' { config.cursor_style = .beam }
		'variable' { config.cursor_style = .variable }
		else { config.cursor_style = .block }
	}
}

// set_tab_size reads editor.tab_size from conf.toml, falling back to 4.
fn (mut config Config) set_tab_size() {
	toml_tab_size := config.settings.value('editor.tab_size').int()
	config.tab_size = if toml_tab_size > 0 { toml_tab_size } else { 4 }
}

// set_backspace_behaviour reads editor.backspace_go_up from conf.toml.
fn (mut config Config) set_backspace_behaviour() {
	config.backspace_go_up = config.settings.value('editor.backspace_go_up').bool()
}

// set_text_metrics resolves text_size/line_height/char_width. The live
// session state (Config2, saved whenever the user resizes text at runtime)
// takes priority since it reflects the most recent explicit choice; conf.toml
// is the fallback for a field the session hasn't set yet; a hardcoded
// literal is the last resort.
fn (mut config Config) set_text_metrics(session Config2) {
	config.text_size = if session.text_size > 0 {
		session.text_size
	} else {
		toml_val := config.settings.value('editor.text_size').int()
		if toml_val > 0 {
			toml_val
		} else {
			min_text_size
		}
	}
	config.line_height = if session.line_height > 0 {
		session.line_height
	} else {
		toml_val := config.settings.value('editor.line_height').int()
		if toml_val > 0 {
			toml_val
		} else {
			20
		}
	}
	config.char_width = if session.char_width > 0 {
		session.char_width
	} else {
		toml_val := config.settings.value('editor.char_width').int()
		if toml_val > 0 {
			toml_val
		} else {
			8
		}
	}
}

// get_toml_color converts a base16 key color (in hex, e.g. colors.base0B)
// to a gg.Color. Returns an error if conf.toml doesn't define it.
fn (config Config) get_toml_color(base string) !gg.Color {
	val := config.settings.value_opt('colors.base${base}') or {
		return error('no colors.base${base} in conf.toml')
	}
	toml_hex := val.string()
	if toml_hex.len < 6 {
		return error('invalid hex color for base${base}: "${toml_hex}"')
	}
	toml_red := ('0x' + toml_hex[0..2]).u8()
	toml_green := ('0x' + toml_hex[2..4]).u8()
	toml_blue := ('0x' + toml_hex[4..6]).u8()
	return gg.rgb(toml_red, toml_green, toml_blue)
}

// base 02
fn (mut config Config) set_vcolor() {
	config.vcolor = config.get_toml_color('02') or {
		if !config.dark_mode {
			gg.rgb(226, 233, 241)
		} else {
			gg.rgb(60, 60, 60)
		}
	}
}

fn (mut config Config) set_split() {
	if !config.dark_mode {
		config.split_color = gg.rgb(223, 223, 223)
	} else {
		config.split_color = gg.rgb(50, 50, 50)
	}
}

// base 00
fn (mut config Config) set_bgcolor() {
	config.bgcolor = config.get_toml_color('00') or {
		if config.dark_mode {
			gg.rgb(30, 30, 30)
		} else {
			gg.rgb(245, 245, 245)
		}
	}
}

// base 08
fn (mut config Config) set_errorbgcolor() {
	config.errorbgcolor = config.get_toml_color('08') or { gg.rgb(240, 0, 0) }
}

// base 0B
fn (mut config Config) set_string() {
	config.string_color = config.get_toml_color('0B') or { gg.rgb(179, 58, 44) }
	config.string_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.string_color
	}
}

// base 0E
fn (mut config Config) set_key() {
	config.key_color = config.get_toml_color('0E') or { gg.rgb(74, 103, 154) }

	config.key_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.key_color
	}
}

// base 0F
fn (mut config Config) set_lit() {
	config.lit_color = config.get_toml_color('0F') or { gg.rgb(7, 103, 154) }

	config.lit_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.lit_color
	}
}

// base 04
fn (mut config Config) set_title() {
	// config.title_color = config.get_toml_color('04') or { gx.rgb(40, 40, 40) }
	config.title_color = gg.rgb(0, 0, 0)
}

// base 05
fn (mut config Config) set_cursor() {
	config.cursor_color = config.get_toml_color('05') or {
		if !config.dark_mode {
			gg.black
		} else {
			gg.white
		}
	}
}

// base 05 (again)
fn (mut config Config) set_txt() {
	config.text_color = config.get_toml_color('05') or {
		if !config.dark_mode {
			gg.black
		} else {
			gg.rgb(212, 212, 212)
		}
	}

	config.txt_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.text_color
	}
}

// base 03
fn (mut config Config) set_comment() {
	config.comment_color = config.get_toml_color('03') or { gg.dark_gray }

	config.comment_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.comment_color
	}
}

fn (mut config Config) set_filename() {
	config.file_name_color = gg.white
	config.file_name_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.file_name_color
	}
}

fn (mut config Config) set_plus() {
	config.plus_color = gg.green
	config.plus_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.plus_color
	}
}

fn (mut config Config) set_minus() {
	config.minus_color = gg.green
	config.minus_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.minus_color
	}
}

// base 01
fn (mut config Config) set_line_nr() {
	config.line_nr_color = config.get_toml_color('01') or { gg.dark_gray }

	config.line_nr_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.line_nr_color
		align: gg.align_right
	}
}

// base 0B
fn (mut config Config) set_green() {
	config.green_color = config.get_toml_color('0B') or { gg.green }

	config.green_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.green_color
	}
}

// base 08
fn (mut config Config) set_red() {
	config.red_color = config.get_toml_color('08') or { gg.red }
	config.red_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.red_color
	}
}

// load_config2 loads the JSON session state (config_path2) and conf.toml
// (config_path), then resolves ved.cfg from both.
fn (mut ved Ved) load_config2() {
	mut session := Config2{}
	if os.exists(config_path2) {
		if conf2 := json2.decode[Config2](os.read_file(config_path2) or { '' }) {
			session = conf2
		} else {
			println(err)
		}
	}
	ved.cfg.disable_fmt = session.disable_fmt
	ved.cfg.set_default_values(session)
}

fn (mut ved Ved) save_config2() {
	config2 := Config2{
		text_size:   ved.cfg.text_size
		disable_fmt: ved.cfg.disable_fmt
		line_height: ved.cfg.line_height
		char_width:  ved.cfg.char_width
	}
	os.write_file(config_path2, json2.encode(config2, prettify: true)) or { panic(err) }
}
