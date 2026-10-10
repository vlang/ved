module main

import gg
import os

const startup_root = os.join_path(os.vtmp_dir(), 'ved_startup_test_${os.getpid()}')

fn testsuite_end() {
	os.rmdir_all(startup_root) or {}
}

fn session_fixture(name string, splits int) ([]string, []string) {
	mut workspaces := []string{}
	mut rows := []string{}
	for workspace_name in ['A', 'B'] {
		workspace := os.join_path(startup_root, name, workspace_name)
		os.mkdir_all(workspace) or { panic(err) }
		workspaces << workspace
		for split in 0 .. splits {
			path := os.join_path(workspace, '${workspace_name}${split + 1}.txt')
			os.write_file(path, 'zero\none\ntwo\nthree\n') or { panic(err) }
			rows << '${path}:${split + 1}'
		}
	}
	return workspaces, rows
}

fn session_editor(workspaces []string, splits int) &Ved {
	mut ved := &Ved{
		workspace:   workspaces[0]
		workspaces:  workspaces.clone()
		nr_splits:   splits
		page_height: 20
		open_paths:  [][]string{len: max_nr_workspaces}
		gg:          &gg.Context{}
	}
	for _ in workspaces {
		for _ in 0 .. splits {
			ved.views << ved.new_view()
		}
	}
	ved.update_view()
	return ved
}

fn test_session_reduces_splits_by_workspace_and_retains_hidden_views() {
	workspaces, rows := session_fixture('reduce', 3)
	mut ved := session_editor(workspaces, 1)
	ved.load_views(rows, workspaces)
	assert !ved.loading_session
	assert !ved.invalid_session
	assert ved.views.map(it.path) == [rows[0].all_before_last(':'), rows[3].all_before_last(':')]
	assert ved.views.map(it.y) == [1, 1]
	assert ved.open_paths[0] == ['A1.txt']
	assert ved.open_paths[1] == ['B1.txt']
	assert ved.workspace_idx == 0
	assert ved.workspace == workspaces[0]
	assert ved.view.path == ved.views[0].path
	assert ved.session_lines() == rows

	// A normal save must retain the hidden panes, including their cursor positions.
	ved.views[0].y = 2
	mut saved := rows.clone()
	saved[0] = '${ved.views[0].path}:2'
	assert ved.session_lines() == saved
	mut fullscreen := session_editor(workspaces, 3)
	fullscreen.load_views(ved.session_lines(), workspaces)
	assert fullscreen.views.map(it.path) == saved.map(it.all_before_last(':'))
	assert fullscreen.views.map(it.y) == [2, 2, 3, 1, 2, 3]
}

fn test_session_expands_splits_without_moving_the_next_workspace() {
	workspaces, rows := session_fixture('expand', 1)
	mut ved := session_editor(workspaces, 3)
	ved.load_views(rows, workspaces)
	assert ved.views.map(it.path) == [rows[0].all_before_last(':'), '', '',
		rows[1].all_before_last(':'), '', '']
	assert ved.session_lines() == [rows[0], ':0', ':0', rows[1], ':0', ':0']
}

fn test_session_matches_reordered_and_duplicate_workspaces() {
	workspaces, rows := session_fixture('reorder', 1)
	mut reordered := session_editor([workspaces[1], workspaces[0]], 1)
	reordered.load_views(rows, workspaces)
	assert reordered.views.map(it.path) == [rows[1].all_before_last(':'), rows[0].all_before_last(':')]
	assert reordered.open_paths[0] == ['B1.txt']
	assert reordered.open_paths[1] == ['A1.txt']
	assert reordered.session_lines() == [rows[1], rows[0]]

	// Separate panes of the same root may have different files, even outside that root.
	duplicate_workspaces := [workspaces[0], workspaces[0]]
	mut duplicate := session_editor(duplicate_workspaces, 1)
	duplicate.load_views(rows, duplicate_workspaces)
	assert duplicate.views.map(it.path) == rows.map(it.all_before_last(':'))
	assert duplicate.session_lines() == rows
}

fn test_session_keeps_empty_and_transient_slots_in_the_workspace_stride() {
	workspaces, rows := session_fixture('empty', 3)
	mut saved := rows.clone()
	saved[0] = ':0'
	saved[1] = ':0'
	mut ved := session_editor(workspaces, 3)
	ved.load_views(saved, workspaces)
	assert ved.views[0].path == ''
	assert ved.views[1].path == ''
	assert ved.views[3].path == rows[3].all_before_last(':')
	ved.views[2].path = 'out'
	saved[2] = ':0'
	assert ved.session_lines() == saved

	// Changing the display count does not change the allocation or saved ownership.
	ved.nr_splits = 2
	assert ved.session_lines() == saved
}

fn test_session_preserves_colons_in_paths() {
	mut ved := session_editor([startup_root], 1)
	ved.load_views(['C:\\ved\\file.txt:0'], [startup_root])
	assert ved.views[0].path == 'C:\\ved\\file.txt'
	assert ved.session_lines() == ['C:\\ved\\file.txt:0']
}

fn test_ambiguous_legacy_session_is_not_overwritten() {
	mut ved := session_editor(['A', 'B'], 1)
	ved.load_views(['A1:0', 'A2:0', 'B1:0'], ['A', 'B'])
	assert ved.invalid_session
	assert ved.views.map(it.path) == ['', '']
	// This must return before any settings files are opened or replaced.
	ved.save_session()
}

fn test_query_dialogs_fit_the_default_window() {
	for kind in [QueryType.ctrlp, .ctrlj, .grep] {
		ved := &Ved{
			query_type: kind
			win_width:  770
			win_height: 480
		}
		layout := ved.query_layout()
		assert layout.x >= 0
		assert layout.y >= 0
		assert layout.x + layout.width <= ved.win_width
		assert layout.y + layout.height <= ved.win_height
		assert layout.y + ved.cfg.line_height * 2 < ved.win_height
		assert layout.result_limit == 16
		result_bottom := layout.y + 2 * ved.cfg.line_height + line_padding +
			layout.result_limit * (ved.cfg.line_height + line_padding)
		assert result_bottom <= layout.y + layout.height
		if kind == .grep {
			assert layout.width == 750
		}
	}
}

fn test_query_scrolling_uses_the_rows_that_fit() {
	for kind in [QueryType.ctrlp, .grep] {
		for height in [480, 240] {
			mut ved := &Ved{
				mode:          .query
				query_type:    kind
				win_width:     770
				win_height:    height
				gg_pos:        -1
				gg_lines:      []string{len: 40, init: 'file:1:match'}
				ctrlp_results: []CtrlPResult{len: 40}
			}
			visible := ved.query_layout().result_limit
			for _ in 0 .. 25 {
				ved.key_query(.down, false)
				assert ved.gg_pos >= ved.gg_scroll
				assert ved.gg_pos < ved.gg_scroll + visible
			}
			assert ved.gg_pos == 24
			assert ved.gg_scroll == 25 - visible
			for _ in 0 .. 16 {
				ved.key_query(.tab, false)
			}
			assert ved.gg_pos == 0
			assert ved.gg_scroll == 0
		}
	}
}

fn test_query_layout_adapts_to_larger_fonts_and_fullscreen() {
	mut ved := &Ved{
		query_type: .grep
		win_width:  770
		win_height: 480
		cfg:        Config{ line_height: 26 }
	}
	layout := ved.query_layout()
	assert layout.result_limit == 12
	assert layout.height <= ved.win_height
	ved.win_width = 2000
	ved.win_height = 1000
	assert ved.query_layout().result_limit == max_grep_lines
	assert ved.query_layout().width == 1400
}

fn test_long_query_results_fit_beside_the_line_count() {
	for width in [320, 750, 1400] {
		for char_width in [8, 10] {
			columns := query_result_columns(width, char_width, 123456)
			prefix, text := fit_grep_result('very_long_directory/'.repeat(10) + 'file.v',
				'1234', 'long matching source line '.repeat(20), columns)
			assert prefix.len + 2 + text.len <= columns
			// The result must end before the right-aligned LoC column.
			assert 10 + columns * char_width < width - 10 - 6 * char_width
		}
	}
	prefix, text := fit_grep_result('file.v', '3', 'matching code', 40)
	assert prefix == 'file.v:3'
	assert text == 'matching code'
}
