module main

import os
import rand

fn C.umask(mask u32) u32

const root = os.join_path(os.vtmp_dir(), 'ved_save_test')

fn testsuite_begin() {
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	$if !windows {
		C.umask(0o022)
	}
}

fn testsuite_end() {
	os.rmdir_all(root) or {}
}

fn temp_files() []string {
	return (os.ls(root) or { [] }).filter(it.ends_with('.ved-tmp'))
}

fn test_replaces_content() {
	p := os.join_path(root, 'a.txt')
	os.write_file(p, 'old\n')!
	write_lines(p, ['new  ', '\tline'])!
	assert os.read_file(p)! == 'new  \n\tline\n'
	write_lines(os.join_path(root, 'new.txt'), ['x'])!
	assert os.read_file(os.join_path(root, 'new.txt'))! == 'x\n'
	assert temp_files() == []
}

fn test_existing_temp_name_is_not_reused() {
	p := os.join_path(root, 'b.txt')
	os.write_file(p, 'old\n')!
	// Plant a file at exactly the name the next save will pick first.
	rand.seed([u32(7), 7])
	planted := os.join_path(root, '.b.txt.${rand.u32():08x}.ved-tmp')
	os.write_file(planted, 'not yours\n')!
	rand.seed([u32(7), 7])
	write_lines(p, ['new'])!
	assert os.read_file(p)! == 'new\n'
	assert os.read_file(planted)! == 'not yours\n'
	os.rm(planted)!
	// The old fixed temporary name must not be touched either.
	$if !windows {
		old_tmp := os.join_path(root, '.b.txt.ved-tmp')
		os.symlink(p, old_tmp)!
		write_lines(p, ['newer'])!
		assert os.read_file(p)! == 'newer\n'
		assert os.is_link(old_tmp)
		os.rm(old_tmp)!
	}
	assert temp_files() == []
}

fn test_concurrent_saves() {
	p := os.join_path(root, 'c.txt')
	a := []string{len: 2000, init: 'aaaaaaaaaaaaaaaa${index}'}
	b := []string{len: 3000, init: 'bbbbbbbbbbbbbbbb${index}'}
	mut threads := []thread !{}
	for i in 0 .. 8 {
		lines := if i % 2 == 0 { a } else { b }
		threads << spawn fn (p string, lines []string) ! {
			for _ in 0 .. 20 {
				write_lines(p, lines)!
			}
		}(p, lines)
	}
	for t in threads {
		t.wait()!
	}
	content := os.read_file(p)!
	assert content == a.join_lines() + '\n' || content == b.join_lines() + '\n'
	assert temp_files() == []
}

fn test_private_file_stays_private() {
	$if !windows {
		p := os.join_path(root, 'secret.txt')
		os.write_file(p, 'old\n')!
		os.chmod(p, 0o600)!
		tmp, fd := create_temp_file(p, 0o600)!
		assert os.stat(tmp)!.mode & 0o777 == 0o600
		write_and_close(fd, []u8{})!
		os.rm(tmp)!
		write_lines(p, ['new'])!
		assert os.stat(p)!.mode & 0o777 == 0o600
		exe := os.join_path(root, 'run.sh')
		os.write_file(exe, '')!
		os.chmod(exe, 0o755)!
		write_lines(exe, ['echo'])!
		assert os.stat(exe)!.mode & 0o777 == 0o755
		fresh := os.join_path(root, 'fresh.txt')
		write_lines(fresh, ['x'])!
		assert os.stat(fresh)!.mode & 0o777 == 0o644
	}
}

fn test_symlink_target_is_updated() {
	$if !windows {
		real := os.join_path(root, 'real.txt')
		link := os.join_path(root, 'link.txt')
		os.write_file(real, 'old\n')!
		os.symlink(real, link)!
		write_lines(link, ['new'])!
		assert os.is_link(link)
		assert os.read_file(real)! == 'new\n'
	}
}

fn test_failed_replace_keeps_original() {
	d := os.join_path(root, 'dir')
	os.mkdir_all(os.join_path(d, 'inner'))!
	write_lines(d, ['x']) or {
		assert os.is_dir(os.join_path(d, 'inner'))
		assert temp_files() == []
		$if windows {
			p := os.join_path(root, 'locked.txt')
			os.write_file(p, 'keep\n')!
			mut f := os.open(p)!
			write_lines(p, ['new']) or {
				f.close()
				assert os.read_file(p)! == 'keep\n'
				assert temp_files() == []
				return
			}
			f.close()
			assert false, 'replacing an open file should fail on windows'
		}
		return
	}
	assert false, 'replacing a directory should fail'
}

fn test_unwritable_dir_fails_cleanly() {
	$if !windows {
		d := os.join_path(root, 'ro')
		os.mkdir(d)!
		p := os.join_path(d, 'f.txt')
		os.write_file(p, 'keep\n')!
		os.chmod(d, 0o555)!
		defer {
			os.chmod(d, 0o755) or {}
		}
		write_lines(p, ['new']) or {
			assert os.read_file(p)! == 'keep\n'
			return
		}
		assert false
	}
}
