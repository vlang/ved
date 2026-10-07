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

// The default save writes into the existing file.

fn test_in_place_save_rewrites_the_same_file() {
	p := os.join_path(root, 'in_place.txt')
	os.write_file(p, 'old old old\n')!
	inode := os.stat(p)!.inode
	write_lines(p, ['new  ', '\tline'])!
	assert os.read_file(p)! == 'new  \n\tline\n'
	assert os.stat(p)!.inode == inode
	write_lines(os.join_path(root, 'in_place_new.txt'), ['x'])!
	assert os.read_file(os.join_path(root, 'in_place_new.txt'))! == 'x\n'
	assert temp_files() == []
}

fn test_in_place_save_keeps_hard_links_in_sync() {
	p := os.join_path(root, 'in_place_linked.txt')
	other := os.join_path(root, 'in_place_other_name.txt')
	os.write_file(p, 'old\n')!
	os.link(p, other) or {
		eprintln('skipping: hard links are not supported here: ${err.msg()}')
		return
	}
	write_lines(p, ['new'])!
	assert os.read_file(other)! == 'new\n'
}

fn test_in_place_save_in_read_only_dir() {
	$if !windows {
		// root can write anywhere.
		if os.getuid() == 0 {
			return
		}
		d := os.join_path(root, 'in_place_ro')
		os.mkdir(d)!
		p := os.join_path(d, 'f.txt')
		os.write_file(p, 'old\n')!
		os.chmod(d, 0o555)!
		defer {
			os.chmod(d, 0o755) or {}
		}
		write_lines(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		write_lines_atomic(p, ['newer']) or {
			assert os.read_file(p)! == 'new\n'
			return
		}
		assert false, 'an atomic save should fail in a folder that is not writable'
	}
}

// With atomic_save set in config.json, saving goes through a temporary file.

fn test_replaces_content() {
	p := os.join_path(root, 'a.txt')
	os.write_file(p, 'old\n')!
	write_lines_atomic(p, ['new  ', '\tline'])!
	assert os.read_file(p)! == 'new  \n\tline\n'
	write_lines_atomic(os.join_path(root, 'new.txt'), ['x'])!
	assert os.read_file(os.join_path(root, 'new.txt'))! == 'x\n'
	assert temp_files() == []
}

fn test_existing_temp_name_is_not_reused() {
	p := os.join_path(root, 'b.txt')
	os.write_file(p, 'old\n')!
	// Plant a file at exactly the name the next save will pick first.
	rand.seed([u32(7), 7])
	planted := os.join_path(root, '.ved-${rand.u64():016x}.ved-tmp')
	os.write_file(planted, 'not yours\n')!
	rand.seed([u32(7), 7])
	write_lines_atomic(p, ['new'])!
	assert os.read_file(p)! == 'new\n'
	assert os.read_file(planted)! == 'not yours\n'
	os.rm(planted)!
	// A symlink at that name must not be followed either.
	$if !windows {
		os.symlink(p, planted)!
		rand.seed([u32(7), 7])
		write_lines_atomic(p, ['newer'])!
		assert os.read_file(p)! == 'newer\n'
		assert os.is_link(planted)
		os.rm(planted)!
	}
	assert temp_files() == []
}

fn test_name_near_name_max() {
	$if !windows {
		p := os.join_path(root, 'n'.repeat(251) + '.txt')
		os.write_file(p, 'old\n')!
		write_lines_atomic(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		write_lines(p, ['newer'])!
		assert os.read_file(p)! == 'newer\n'
		assert temp_files() == []
	}
}

fn test_concurrent_saves() {
	p := os.join_path(root, 'c.txt')
	a := []string{len: 2000, init: 'aaaaaaaaaaaaaaaa${index}'}
	b := []string{len: 3000, init: 'bbbbbbbbbbbbbbbb${index}'}
	mut threads := []thread int{}
	for i in 0 .. 8 {
		lines := if i % 2 == 0 { a } else { b }
		threads << spawn fn (p string, lines []string) int {
			mut failed := 0
			for _ in 0 .. 20 {
				write_lines_atomic(p, lines) or { failed++ }
			}
			return failed
		}(p, lines)
	}
	mut failed := 0
	for t in threads {
		failed += t.wait()
	}
	$if windows {
		assert failed < 8 * 20
	} $else {
		assert failed == 0
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
		tmp, fd := create_temp_file(p, 0o600, []u8{})!
		assert os.stat(tmp)!.mode & 0o777 == 0o600
		finish_temp_file(fd, tmp, p, []u8{}, none)!
		os.rm(tmp)!
		write_lines_atomic(p, ['new'])!
		assert os.stat(p)!.mode & 0o777 == 0o600
		exe := os.join_path(root, 'run.sh')
		os.write_file(exe, '')!
		os.chmod(exe, 0o755)!
		write_lines_atomic(exe, ['echo'])!
		assert os.stat(exe)!.mode & 0o777 == 0o755
		fresh := os.join_path(root, 'fresh.txt')
		write_lines_atomic(fresh, ['x'])!
		assert os.stat(fresh)!.mode & 0o777 == 0o644
	}
}

fn test_owner_and_group_are_kept() {
	$if !windows {
		p := os.join_path(root, 'shared.txt')
		os.write_file(p, 'old\n')!
		st := os.stat(p)!
		groups := os.exec(['id', '-G']).output.fields().map(it.u32())
		other := groups.filter(it != st.gid)
		if other.len == 0 {
			eprintln('skipping: the user is in a single group')
			return
		}
		os.chown(p, int(st.uid), int(other[0]))!
		os.chmod(p, 0o640)!
		write_lines_atomic(p, ['new'])!
		after := os.stat(p)!
		assert after.uid == st.uid
		assert after.gid == other[0]
		assert after.mode & 0o777 == 0o640
		assert os.read_file(p)! == 'new\n'
	}
}

fn test_read_only_file_is_not_replaced() {
	$if !windows {
		// root can write to any file.
		if os.getuid() == 0 {
			return
		}
	}
	p := os.join_path(root, 'readonly.txt')
	os.write_file(p, 'keep\n')!
	os.chmod(p, 0o444)!
	defer {
		os.chmod(p, 0o644) or {}
	}
	write_lines_atomic(p, ['new']) or {
		assert os.read_file(p)! == 'keep\n'
		assert temp_files() == []
		return
	}
	assert false, 'saving a read-only file should fail'
}

fn test_hard_linked_file_is_not_replaced() {
	p := os.join_path(root, 'linked.txt')
	other := os.join_path(root, 'other_name.txt')
	os.write_file(p, 'keep\n')!
	os.link(p, other) or {
		eprintln('skipping: hard links are not supported here: ${err.msg()}')
		return
	}
	write_lines_atomic(p, ['new']) or {
		assert err.msg().contains('hard links')
		assert os.read_file(p)! == 'keep\n'
		assert os.read_file(other)! == 'keep\n'
		assert temp_files() == []
		return
	}
	assert false, 'saving a hard-linked file should fail'
}

fn C.setxattr(path &char, name &char, value voidptr, size usize, flags i32) i32

fn test_file_capabilities_are_dropped_like_a_normal_write() {
	$if linux {
		// Setting a file capability needs root (CAP_SETFCAP).
		if os.getuid() != 0 {
			eprintln('skipping: setting file capabilities needs root')
			return
		}
		replaced := os.join_path(root, 'cap_atomic')
		in_place := os.join_path(root, 'cap_in_place')
		for p in [replaced, in_place] {
			os.write_file(p, 'echo old\n')!
			os.chmod(p, 0o755)!
			if os.exec(['setcap', 'cap_net_raw+ep', p]).exit_code != 0 {
				eprintln('skipping: setcap is not available or the filesystem has no capabilities')
				return
			}
		}
		write_lines_atomic(replaced, ['echo new'])!
		write_lines(in_place, ['echo new'])!
		assert read_xattr(in_place, -1, 'security.capability') or { []u8{} } == []u8{}
		assert read_xattr(replaced, -1, 'security.capability') or { []u8{} } == []u8{}
	}
}

fn test_acl_and_xattrs_are_kept() {
	$if linux {
		p := os.join_path(root, 'acl.txt')
		os.write_file(p, 'old\n')!
		os.chmod(p, 0o640)!
		if os.exec(['setfacl', '-m', 'u:65534:r--', p]).exit_code != 0 {
			eprintln('skipping: setfacl is not available or the filesystem has no ACLs')
			return
		}
		value := 'kept'
		if C.setxattr(&char(p.str), c'user.ved_test', value.str, usize(value.len), 0) != 0 {
			eprintln('skipping: the filesystem has no user extended attributes')
			return
		}
		acl_before := os.exec(['getfacl', '-c', p]).output
		mode_before := os.stat(p)!.mode & 0o7777
		write_lines_atomic(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		assert os.exec(['getfacl', '-c', p]).output == acl_before
		assert os.stat(p)!.mode & 0o7777 == mode_before
		assert read_xattr(p, -1, 'user.ved_test')!.bytestr() == value
	}
}

fn test_inode_flags_are_kept() {
	$if linux {
		p := os.join_path(root, 'nodump.txt')
		os.write_file(p, 'old\n')!
		if os.exec(['chattr', '+dA', p]).exit_code != 0 {
			eprintln('skipping: chattr is not available or the filesystem has no inode flags')
			return
		}
		flags_before := os.exec(['lsattr', p]).output.fields()[0]
		assert flags_before.contains('d') && flags_before.contains('A')
		write_lines_atomic(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		assert os.exec(['lsattr', p]).output.fields()[0] == flags_before
	}
}

fn test_inherited_acl_is_not_added() {
	$if linux {
		d := os.join_path(root, 'default_acl')
		os.mkdir(d)!
		p := os.join_path(d, 'plain.txt')
		os.write_file(p, 'old\n')!
		if os.exec(['setfacl', '-d', '-m', 'u:65534:rw-', d]).exit_code != 0
			|| os.exec(['setfacl', '-b', p]).exit_code != 0 {
			eprintln('skipping: setfacl is not available or the filesystem has no ACLs')
			return
		}
		os.chmod(p, 0o640)!
		acl_before := os.exec(['getfacl', '-c', p]).output
		assert !acl_before.contains('65534')
		write_lines_atomic(p, ['new'])!
		assert os.exec(['getfacl', '-c', p]).output == acl_before
		assert os.stat(p)!.mode & 0o7777 == 0o640
	}
}

fn test_load_lines() {
	assert load_lines(os.join_path(root, 'does_not_exist.txt'))! == []string{}
	p := os.join_path(root, 'lines.txt')
	os.write_file(p, 'a\nb\n')!
	assert load_lines(p)! == ['a', 'b']
	$if !windows {
		if os.getuid() == 0 {
			return
		}
		d := os.join_path(root, 'closed')
		os.mkdir(d)!
		os.write_file(os.join_path(d, 'f.txt'), 'data\n')!
		os.chmod(d, 0o600)!
		defer {
			os.chmod(d, 0o755) or {}
		}
		load_lines(os.join_path(d, 'f.txt')) or {
			assert !err.msg().contains('No such file')
			return
		}
		assert false, 'a file in a directory that cannot be entered must not load as empty'
	}
}

fn test_windows_write_denied_file_is_not_replaced() {
	$if windows {
		p := os.join_path(root, 'denied.txt')
		os.write_file(p, 'keep\n')!
		set_dacl(p, 'D:P(D;;FW;;;WD)(A;;FA;;;WD)')
		write_lines_atomic(p, ['new']) or {
			assert os.read_file(p)! == 'keep\n'
			assert temp_files() == []
			return
		}
		assert false, 'saving a file denied for writing should fail'
	}
}

fn C.SetFileAttributesW(path &u16, attrs u32) bool
fn C.EncryptFileW(path &u16) bool

fn file_attributes(path string) u32 {
	$if windows {
		return C.GetFileAttributesW(&u8(path.replace('/', '\\').to_wide()))
	}
	return 0
}

fn test_windows_attributes_and_streams_are_kept() {
	$if windows {
		p := os.join_path(root, 'marked.txt')
		os.write_file(p, 'old\n')!
		os.write_file(p + ':ved_test', 'stream') or {
			eprintln('skipping: the filesystem has no alternate data streams')
			return
		}
		assert C.SetFileAttributesW(p.replace('/', '\\').to_wide(), C.FILE_ATTRIBUTE_HIDDEN)
		write_lines_atomic(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		assert file_attributes(p) & C.FILE_ATTRIBUTE_HIDDEN != 0
		assert os.read_file(p + ':ved_test')! == 'stream'
	}
}

fn test_windows_encryption_is_kept() {
	$if windows {
		p := os.join_path(root, 'encrypted.txt')
		os.write_file(p, 'secret\n')!
		if !C.EncryptFileW(p.replace('/', '\\').to_wide()) {
			eprintln('skipping: EFS is not available')
			return
		}
		assert file_attributes(p) & C.FILE_ATTRIBUTE_ENCRYPTED != 0
		tmp, fd := create_temp_file(p, 0o600, security_descriptor(p)!)!
		assert file_attributes(tmp) & C.FILE_ATTRIBUTE_ENCRYPTED != 0
		finish_temp_file(fd, tmp, p, []u8{}, none)!
		os.rm(tmp)!
		write_lines_atomic(p, ['new'])!
		assert os.read_file(p)! == 'new\n'
		assert file_attributes(p) & C.FILE_ATTRIBUTE_ENCRYPTED != 0
	}
}

fn test_windows_security_is_kept() {
	$if windows {
		p := os.join_path(root, 'private.txt')
		os.write_file(p, 'old\n')!
		set_dacl(p, 'D:P(A;;FA;;;WD)')
		before := sd_string(p)
		assert before.starts_with('O:')
		assert before.contains('D:P')
		tmp, fd := create_temp_file(p, 0o600, security_descriptor(p)!)!
		assert sd_string(tmp) == before
		finish_temp_file(fd, tmp, p, []u8{}, none)!
		os.rm(tmp)!
		write_lines_atomic(p, ['new'])!
		assert sd_string(p) == before
		assert os.read_file(p)! == 'new\n'
	}
}

fn test_windows_foreign_owner_is_refused() {
	$if windows {
		p := os.getenv('VED_FOREIGN_OWNER_FILE')
		if p == '' {
			eprintln('skipping: VED_FOREIGN_OWNER_FILE is not set')
			return
		}
		before_sd := sd_string(p)
		before := os.read_file(p)!
		write_lines_atomic(p, ['new']) or {
			assert err.msg().contains('owner')
			assert os.read_file(p)! == before
			assert sd_string(p) == before_sd
			return
		}
		assert false, 'saving a file owned by another account should fail'
	}
}

$if windows && !tinyc {
	#include <sddl.h>
}

fn C.ConvertStringSecurityDescriptorToSecurityDescriptorW(s &u16, rev u32, sd &voidptr, size &u32) bool
fn C.ConvertSecurityDescriptorToStringSecurityDescriptorW(sd voidptr, rev u32, info u32, s &&u16, len &u32) bool
fn C.SetFileSecurityW(name &u16, info u32, sd voidptr) bool
fn C.LocalFree(mem voidptr) voidptr

fn set_dacl(path string, sddl string) {
	$if windows {
		mut sd := unsafe { nil }
		assert C.ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.to_wide(), 1, &sd,
			unsafe { nil })
		assert C.SetFileSecurityW(path.replace('/', '\\').to_wide(), u32(C.DACL_SECURITY_INFORMATION),
			sd)
		C.LocalFree(sd)
	}
}

fn sd_string(path string) string {
	$if windows {
		sd := security_descriptor(path) or { panic(err) }
		mut s := &u16(unsafe { nil })
		info := u32(C.OWNER_SECURITY_INFORMATION | C.GROUP_SECURITY_INFORMATION | C.DACL_SECURITY_INFORMATION)
		assert C.ConvertSecurityDescriptorToStringSecurityDescriptorW(sd.data, 1, info, &s,
			unsafe { nil })
		res := unsafe { string_from_wide(s) }
		C.LocalFree(s)
		return res
	}
	return ''
}

fn test_symlink_target_is_updated() {
	$if !windows {
		real := os.join_path(root, 'real.txt')
		link := os.join_path(root, 'link.txt')
		os.write_file(real, 'old\n')!
		os.symlink(real, link)!
		write_lines_atomic(link, ['new'])!
		assert os.is_link(link)
		assert os.read_file(real)! == 'new\n'
	}
}

fn test_dangling_symlink_creates_its_target() {
	$if !windows {
		d := os.join_path(root, 'dangling')
		os.mkdir_all(os.join_path(d, 'sub'))!
		link := os.join_path(d, 'link.txt')
		os.symlink('sub/new.txt', link)!
		write_lines_atomic(link, ['new'])!
		assert os.is_link(link)
		assert os.read_file(os.join_path(d, 'sub', 'new.txt'))! == 'new\n'
		first := os.join_path(d, 'first.txt')
		os.symlink('second.txt', first)!
		os.symlink('sub/chained.txt', os.join_path(d, 'second.txt'))!
		write_lines_atomic(first, ['chained'])!
		assert os.is_link(first)
		assert os.read_file(os.join_path(d, 'sub', 'chained.txt'))! == 'chained\n'
		loop := os.join_path(d, 'loop.txt')
		os.symlink('loop.txt', loop)!
		write_lines_atomic(loop, ['x']) or {
			assert os.is_link(loop)
			return
		}
		assert false, 'saving through a symlink loop should fail'
	}
}

fn test_failed_replace_keeps_original() {
	d := os.join_path(root, 'dir')
	os.mkdir_all(os.join_path(d, 'inner'))!
	write_lines_atomic(d, ['x']) or {
		assert os.is_dir(os.join_path(d, 'inner'))
		assert temp_files() == []
		$if windows {
			p := os.join_path(root, 'locked.txt')
			os.write_file(p, 'keep\n')!
			mut f := os.open(p)!
			write_lines_atomic(p, ['new']) or {
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
