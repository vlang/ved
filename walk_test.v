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

fn test_unreadable_folders_make_the_walk_partial() {
	$if windows {
		return
	}
	// root can read anything.
	if os.getuid() == 0 {
		return
	}
	d := fresh_dir('unreadable')
	os.write_file(os.join_path(d, 'a.v'), '')!
	// Can't be listed at all.
	closed := os.join_path(d, 'closed')
	os.mkdir(closed)!
	os.write_file(os.join_path(closed, 'hidden_from_walk.v'), '')!
	os.chmod(closed, 0)!
	defer {
		os.chmod(closed, 0o755) or {}
	}
	files, partial := walk_workspace_files(d)
	assert files == ['a.v']
	assert partial
	os.chmod(closed, 0o755)!
	// Can be listed, but not entered: every entry's stat fails.
	os.chmod(closed, 0o644)!
	files2, partial2 := walk_workspace_files(d)
	assert files2 == ['a.v']
	assert partial2
	os.chmod(closed, 0o755)!
	// Readable again: complete.
	files3, partial3 := walk_workspace_files(d)
	assert files3.len == 2
	assert !partial3
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

fn test_file_names_are_kept_exactly() {
	$if windows {
		return
	}
	names := [' lead.v', 'trail.v ', 'new\nline.v']
	plain := fresh_dir('exact_plain')
	for name in names {
		os.write_file(os.join_path(plain, name), '')!
	}
	mut walked, _ := walk_workspace_files(plain)
	walked.sort()
	mut want := names.clone()
	want.sort()
	assert walked == want
	if os.find_abs_path_of_executable('git') or { '' } == '' {
		eprintln('skipping the git part: git is not installed')
		return
	}
	repo := fresh_dir('exact_git')
	for name in names {
		os.write_file(os.join_path(repo, name), '')!
	}
	assert os.exec(['git', '-C', repo, 'init', '-q']).exit_code == 0
	assert os.exec(['git', '-C', repo, 'add', '-A']).exit_code == 0
	mut ved := &Ved{
		workspace: repo
	}
	mut listed, _ := ved.get_files_for_workspace(repo)
	listed.sort()
	assert listed == want
	ved.all_git_files = listed
	ved.query = 'LEAD'
	ved.filter_ctrlp_results()
	assert ved.ctrlp_results.map(it.file_path) == [' lead.v']
}

fn test_ctrlp_partial_other_workspace() {
	current := fresh_dir('ctrlp_current')
	os.write_file(os.join_path(current, 'here.v'), '')!
	other := fresh_dir('ctrlp_other')
	for i in 0 .. max_walked_entries + 1 {
		os.write_file(os.join_path(other, 'f${i}.txt'), '')!
	}
	mut ved := &Ved{
		workspace:  current
		workspaces: [current, other]
	}
	ved.all_git_files, ved.all_files_partial = ved.get_files_for_workspace(current)
	ved.query = 'f1'
	ved.filter_ctrlp_results()
	assert ved.ctrlp_results.len > 0
	assert ved.ctrlp_partial
	assert !ved.all_files_partial
	ved.query = 'here'
	ved.filter_ctrlp_results()
	assert ved.ctrlp_results.map(it.file_path) == ['here.v']
	assert !ved.ctrlp_partial
}

fn test_failed_git_listing_is_partial() {
	if os.find_abs_path_of_executable('git') or { '' } == '' {
		eprintln('skipping: git is not installed')
		return
	}
	repo := fresh_dir('corrupt_index')
	os.write_file(os.join_path(repo, 'a.v'), '')!
	assert os.exec(['git', '-C', repo, 'init', '-q']).exit_code == 0
	assert os.exec(['git', '-C', repo, 'add', 'a.v']).exit_code == 0
	// Still a repository, but git ls-files fails.
	os.write_file(os.join_path(repo, '.git', 'index'), 'garbage')!
	ved := &Ved{}
	files, partial := ved.get_files_for_workspace(repo)
	assert files == []string{}
	assert partial
}

fn test_switch_from_git_to_non_git_workspace() {
	git_dir := fresh_dir('repo with space')
	os.write_file(os.join_path(git_dir, 'tracked.v'), '')!
	os.write_file(os.join_path(git_dir, 'untracked.v'), '')!
	os.write_file(os.join_path(git_dir, 'ignored.v'), '')!
	os.write_file(os.join_path(git_dir, '.gitignore'), 'ignored.v\n')!
	assert os.exec(['git', '-C', git_dir, 'init', '-q']).exit_code == 0
	assert os.exec(['git', '-C', git_dir, 'add', 'tracked.v']).exit_code == 0
	plain_dir := fresh_dir('plain')
	os.write_file(os.join_path(plain_dir, 'plain.v'), '')!

	mut ved := &Ved{
		workspace: git_dir
	}
	ved.load_git_tree()
	mut listed := ved.all_git_files.clone()
	listed.sort()
	assert listed == ['.gitignore', 'tracked.v', 'untracked.v']
	ved.workspace = plain_dir
	ved.load_git_tree()
	assert ved.all_git_files == ['plain.v']
	assert !ved.all_files_partial
}
