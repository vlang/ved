module main

import os

fn C.mkfifo(path &char, mode u32) int

const root = os.join_path(os.vtmp_dir(), 'ved_walk_test')

fn fresh_dir(name string) string {
	d := os.join_path(root, name)
	os.rmdir_all(d) or {}
	os.mkdir_all(d) or { panic(err) }
	return d
}

fn testsuite_end() {
	os.rmdir_all(root) or {}
}

fn test_ordinary_tree() {
	d := fresh_dir('tree')
	os.mkdir_all(os.join_path(d, 'src', 'sub'))!
	os.mkdir_all(os.join_path(d, '.git', 'objects'))!
	os.write_file(os.join_path(d, 'a.v'), '')!
	os.write_file(os.join_path(d, 'my file.txt'), '')!
	os.write_file(os.join_path(d, 'src', 'sub', 'b.v'), '')!
	os.write_file(os.join_path(d, '.env'), '')!
	os.write_file(os.join_path(d, '.git', 'objects', 'x'), '')!
	mut files, partial := walk_workspace_files(d)
	files.sort()
	assert files == ['a.v', 'my file.txt', os.join_path('src', 'sub', 'b.v')]
	assert !partial
}

fn test_symlinks() {
	$if windows {
		return
	}
	d := fresh_dir('links')
	os.mkdir_all(os.join_path(d, 'src'))!
	os.write_file(os.join_path(d, 'src', 'a.v'), '')!
	os.symlink(d, os.join_path(d, 'src', 'loop'))!
	os.symlink(os.join_path(d, 'src', 'a.v'), os.join_path(d, 'link.v'))!
	os.symlink(os.join_path(d, 'missing'), os.join_path(d, 'broken.v'))!
	mut files, partial := walk_workspace_files(d)
	files.sort()
	assert files == ['link.v', os.join_path('src', 'a.v')]
	assert !partial
}

fn test_special_files_are_skipped() {
	$if windows {
		return
	}
	d := fresh_dir('fifo')
	os.write_file(os.join_path(d, 'a.v'), '')!
	fifo := os.join_path(d, 'pipe')
	assert C.mkfifo(&char(fifo.str), 0o644) == 0
	os.symlink(fifo, os.join_path(d, 'pipe_link'))!
	files, _ := walk_workspace_files(d)
	assert files == ['a.v']
}

fn test_entry_budget() {
	d := fresh_dir('many')
	for i in 0 .. max_walked_entries {
		os.write_file(os.join_path(d, '${i}'), '')!
	}
	files, partial := walk_workspace_files(d)
	assert files.len == max_walked_entries
	assert !partial
	os.mkdir(os.join_path(d, 'one_more'))!
	files2, partial2 := walk_workspace_files(d)
	assert files2.len <= max_walked_entries
	assert partial2
}

fn test_switch_from_git_to_non_git_workspace() {
	git_dir := fresh_dir('repo with space')
	os.write_file(os.join_path(git_dir, 'tracked.v'), '')!
	os.write_file(os.join_path(git_dir, 'untracked.v'), '')!
	q := os.quoted_path(git_dir)
	assert os.execute('git -C ${q} init -q && git -C ${q} add tracked.v').exit_code == 0
	plain_dir := fresh_dir('plain')
	os.write_file(os.join_path(plain_dir, 'plain.v'), '')!

	mut ved := &Ved{
		workspace: git_dir
	}
	ved.load_git_tree()
	assert ved.all_git_files == ['tracked.v']
	ved.workspace = plain_dir
	ved.load_git_tree()
	assert ved.all_git_files == ['plain.v']
	assert !ved.all_files_partial
}
