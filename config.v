// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import gg
import toml
import x.json2

// The different kinds of cursors
enum CursorStyle {
	block
	beam
	variable
}

// Config structure
struct Config {
mut:
	dark_mode       bool
	cursor_style    CursorStyle
	text_size       int = min_text_size
	line_height     int = 20
	char_width      int = 8
	tab_size        int = 4
	tab             int = int(`\t`) // TODO read from config file?
	backspace_go_up bool
	vcolor          gg.Color // v selection background color, base02
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
	atomic_save bool // save through a temporary file that replaces the original
	// [colors] from conf.toml by base16 name, e.g. '0B'
	colors map[string]gg.Color @[json: '-']
}

// set_default_values computes the colors and text styles from the settings.
fn (mut config Config) set_default_values() {
	config.init_colors()

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

// color returns the [colors] override for base, e.g. '0B', or the default.
fn (config Config) color(base string, default gg.Color) gg.Color {
	return config.colors[base] or { default }
}

// base 02
fn (mut config Config) set_vcolor() {
	config.vcolor = config.color('02', if !config.dark_mode {
		gg.rgb(226, 233, 241)
	} else {
		gg.rgb(60, 60, 60)
	})
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
	config.bgcolor = config.color('00', if config.dark_mode {
		gg.rgb(30, 30, 30)
	} else {
		gg.rgb(245, 245, 245)
	})
}

// base 08
fn (mut config Config) set_errorbgcolor() {
	config.errorbgcolor = config.color('08', gg.rgb(240, 0, 0))
}

// base 0B
fn (mut config Config) set_string() {
	config.string_color = config.color('0B', gg.rgb(179, 58, 44))
	config.string_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.string_color
	}
}

// base 0E
fn (mut config Config) set_key() {
	config.key_color = config.color('0E', gg.rgb(74, 103, 154))

	config.key_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.key_color
	}
}

// base 0F
fn (mut config Config) set_lit() {
	config.lit_color = config.color('0F', gg.rgb(7, 103, 154))

	config.lit_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.lit_color
	}
}

// base 04
fn (mut config Config) set_title() {
	config.title_color = config.color('04', gg.rgb(0, 0, 0))
}

// base 05
fn (mut config Config) set_cursor() {
	config.cursor_color = config.color('05', if !config.dark_mode {
		gg.black
	} else {
		gg.white
	})
}

// base 05 (again)
fn (mut config Config) set_txt() {
	config.text_color = config.color('05', if !config.dark_mode {
		gg.black
	} else {
		gg.rgb(212, 212, 212)
	})

	config.txt_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.text_color
	}
}

// base 03
fn (mut config Config) set_comment() {
	config.comment_color = config.color('03', gg.dark_gray)

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
	config.line_nr_color = config.color('01', gg.dark_gray)

	config.line_nr_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.line_nr_color
		align: gg.align_right
	}
}

// base 0B
fn (mut config Config) set_green() {
	config.green_color = config.color('0B', gg.green)

	config.green_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.green_color
	}
}

fn (mut config Config) set_red() {
	config.red_color = config.color('08', gg.red)
	config.red_cfg = gg.TextCfg{
		size:  config.text_size
		color: config.red_color
	}
}

// load_config2 loads config.json, then conf.toml on top of it. It runs again after
// every save, so changes to either file apply without a restart.
fn (mut ved Ved) load_config2() {
	ved.cfg = Config{}
	mut zoom_saved := false
	if text := os.read_file(config_path2) {
		if conf2 := json2.decode[Config](text) {
			ved.cfg = conf2
			saved := json2.decode[json2.Any](text) or { json2.Any(map[string]json2.Any{}) }
			zoom_saved = 'text_size' in saved.as_map()
		} else {
			println(err)
		}
	}
	doc := toml.parse_file(config_path) or {
		if os.exists(config_path) {
			ved.error_line = 'conf.toml: ${err.msg()}'
		}
		toml.parse_text('') or { panic(err) }
	}
	ved.cfg.apply_toml_editor(doc, zoom_saved)
	ved.cfg.colors = toml_colors(doc) or {
		ved.error_line = 'conf.toml: ${err.msg()}'
		map[string]gg.Color{}
	}
	ved.cfg.set_default_values()
	// gg keeps its own copy of the background color and doesn't exist yet on the first load.
	if !isnil(ved.gg) {
		ved.gg.set_bg_color(ved.cfg.bgcolor)
	}
}

// apply_toml_editor applies the settings of the [editor] table in conf.toml.
fn (mut config Config) apply_toml_editor(doc toml.Doc, zoom_saved bool) {
	if v := doc.value_opt('editor.dark_mode') {
		config.dark_mode = v.bool()
	}
	if v := doc.value_opt('editor.cursor') {
		config.cursor_style = match v.string() {
			'beam' { .beam }
			'variable' { .variable }
			else { .block }
		}
	}
	if !zoom_saved {
		if n := toml_positive_int(doc, 'editor.text_size') {
			config.text_size = n
		}
		if n := toml_positive_int(doc, 'editor.line_height') {
			config.line_height = n
		}
		if n := toml_positive_int(doc, 'editor.char_width') {
			config.char_width = n
		}
	}
	if n := toml_positive_int(doc, 'editor.tab_size') {
		config.tab_size = n
	}
	if v := doc.value_opt('editor.backspace_go_up') {
		config.backspace_go_up = v.bool()
	}
	if v := doc.value_opt('editor.disable_fmt') {
		config.disable_fmt = v.bool()
	}
	if v := doc.value_opt('editor.atomic_save') {
		config.atomic_save = v.bool()
	}
}

// toml_positive_int returns the integer at key, if it is set and greater than 0.
fn toml_positive_int(doc toml.Doc, key string) ?int {
	n := (doc.value_opt(key) or { return none }).int()
	return if n > 0 { n } else { none }
}

// toml_colors reads the [colors] table of conf.toml: base16 names mapped to hex colors.
fn toml_colors(doc toml.Doc) !map[string]gg.Color {
	mut colors := map[string]gg.Color{}
	table := doc.value_opt('colors') or { return colors }
	for key, value in table.as_map() {
		hex := value.string().trim_left('#')
		if !key.starts_with('base') || hex.len != 6 || !hex.bytes().all(it.is_hex_digit()) {
			return error('invalid color ${key} = "${value.string()}"')
		}
		colors[key[4..].to_upper()] = gg.rgb(u8(hex[0..2].parse_uint(16, 8) or { 0 }),
			u8(hex[2..4].parse_uint(16, 8) or { 0 }), u8(hex[4..6].parse_uint(16, 8) or { 0 }))
	}
	return colors
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
	os.write_file(config_path2, json2.encode(ved.cfg, prettify: true)) or { panic(err) }
}
