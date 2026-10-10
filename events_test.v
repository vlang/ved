module main

import gg

fn new_event_test_ved(workspace_idx int) &Ved {
	mut ved := &Ved{
		win_width:     1200
		win_height:    600
		nr_splits:     2
		workspace_idx: workspace_idx
		cur_split:     workspace_idx * 2
		cfg:           Config{
			disable_mouse: false
		}
	}
	for i in 0 .. (workspace_idx + 1) * 2 {
		ved.views << View{
			ved:          ved
			path:         'view-${i}.txt'
			padding_left: 20
			x:            2
			y:            3
			lines:        []string{len: 30, init: 'abcdefghijklmnopqrstuvwxyz'}
		}
	}
	ved.update_view()
	return ved
}

fn test_mouse_callback_uses_logical_split_and_cursor_coordinates() {
	mut ved := new_event_test_ved(0)
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 700
		mouse_y: 210
	}, ved)
	assert ved.cur_split == 1
	assert ved.view.path == 'view-1.txt'
	assert ved.view.y == 9
	assert ved.view.x == 8
	assert ved.views[0].y == 3
	assert ved.views[0].x == 2
}

fn test_mouse_focus_and_edits_stay_in_the_current_workspace() {
	mut ved := new_event_test_ved(1)
	ved.views[3].from = 5
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 700
		mouse_y: 50
	}, ved)
	assert ved.cur_split == 3
	assert ved.view.path == 'view-3.txt'
	assert ved.view.y == 6
	assert ved.view.x == 8
	ved.char_insert('X')
	assert ved.views[3].lines[6] == 'abcdefghXijklmnopqrstuvwxyz'
	for i in 0 .. 3 {
		assert ved.views[i].y == 3
		assert ved.views[i].x == 2
		assert ved.views[i].lines[6] == 'abcdefghijklmnopqrstuvwxyz'
	}
}

fn test_mouse_column_uses_the_clicked_line_and_configured_tab_width() {
	mut ved := new_event_test_ved(0)
	ved.cfg.tab_size = 8
	ved.views[1].lines[2] = '\t\tabé'
	// The second split's text origin is 630; each expanded tab is 64 pixels wide.
	for i, mouse_x in [662, 726, 758, 774, 900] {
		ved_event(&gg.Event{
			typ:     .mouse_down
			mouse_x: f32(mouse_x)
			mouse_y: 70
		}, ved)
		assert ved.view.y == 2
		assert ved.view.x == [0, 1, 2, 4, 5][i]
	}
}

fn test_mouse_clicks_clamp_cursor_and_respect_disabled_mouse() {
	mut ved := new_event_test_ved(0)
	// A click on the split boundary belongs to the split on its right.
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 600
		mouse_y: 0
	}, ved)
	assert ved.cur_split == 1
	assert ved.view.y == 0
	assert ved.view.x == 0
	ved.views[1].lines = ['a']
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 1100
		mouse_y: 590
	}, ved)
	assert ved.view.y == 0
	assert ved.view.x == 1
	ved.views[1].lines = []
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 700
		mouse_y: 50
	}, ved)
	assert ved.view.y == 0
	assert ved.view.x == 0
	ved.cfg.disable_mouse = true
	ved_event(&gg.Event{
		typ:     .mouse_down
		mouse_x: 100
		mouse_y: 210
	}, ved)
	assert ved.cur_split == 1
	assert ved.views[0].y == 3
	assert ved.views[0].x == 2
}

fn test_resize_callback_keeps_logical_window_dimensions() {
	mut ved := new_event_test_ved(0)
	ved_event(&gg.Event{
		typ:           .resized
		window_width:  1440
		window_height: 900
	}, ved)
	assert ved.win_width == 1440
	assert ved.win_height == 900
}
