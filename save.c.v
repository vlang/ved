module main

import os
import rand
import strings

fn C.fsync(fd i32) i32
fn C._write(fd i32, buf voidptr, count u32) i32
fn C._commit(fd i32) i32
fn C._close(fd i32) i32
fn C.MoveFileExW(existing &u16, new &u16, flags u32) bool

// write_lines replaces the file at path by writing a new temporary file next to it
// and renaming it over the original.
fn write_lines(path string, lines []string) ! {
	// Resolve symlinks, so that the link's target is updated instead of the link
	// being replaced by a regular file.
	target := os.real_path(path)
	old_mode := if st := os.stat(target) { int(st.mode & 0o7777) } else { -1 }
	tmp, fd := create_temp_file(target, if old_mode == -1 { 0o666 } else { 0o600 })!
	mut sb := strings.new_builder(4096)
	for line in lines {
		sb.write_string(line)
		sb.write_u8(`\n`)
	}
	write_and_close(fd, sb) or {
		os.rm(tmp) or {}
		return err
	}
	if old_mode != -1 {
		os.chmod(tmp, old_mode) or {
			os.rm(tmp) or {}
			return err
		}
	}
	replace_file(tmp, target) or {
		os.rm(tmp) or {}
		return err
	}
}

// create_temp_file creates a new file next to target and returns its path and
// descriptor. O_EXCL makes the creation fail instead of reusing an existing file,
// e.g. another save's temporary file or a symlink placed under the same name.
fn create_temp_file(target string, perm int) !(string, int) {
	dir := os.dir(target)
	name := os.file_name(target)
	for _ in 0 .. 100 {
		tmp := os.join_path(dir, '.${name}.${rand.u32():08x}.ved-tmp')
		fd := $if windows {
			C._wopen(tmp.to_wide(), C._O_WRONLY | C._O_CREAT | C._O_EXCL | C._O_BINARY,
				C._S_IREAD | C._S_IWRITE)
		} $else {
			// O_CLOEXEC keeps the descriptor out of formatter and build processes.
			C.open(&char(tmp.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, perm)
		}
		if fd != -1 {
			return tmp, fd
		}
		if C.errno != C.EEXIST {
			return error('cannot create ${tmp}: ${os.posix_get_error_msg(C.errno)}')
		}
	}
	return error('cannot create a temporary file in ${dir}')
}

// write_and_close writes all of data to fd, flushes it to disk and closes fd`.
fn write_and_close(fd int, data []u8) ! {
	mut err_msg := ''
	mut written := 0
	for written < data.len {
		n := $if windows {
			C._write(fd, unsafe { &data[written] }, u32(data.len - written))
		} $else {
			C.write(fd, unsafe { &data[written] }, usize(data.len - written))
		}
		if n < 0 {
			$if !windows {
				if C.errno == C.EINTR {
					continue
				}
			}
			err_msg = os.posix_get_error_msg(C.errno)
			break
		}
		written += n
	}
	if err_msg == '' {
		synced := $if windows { C._commit(fd) } $else { C.fsync(fd) }
		if synced != 0 {
			err_msg = os.posix_get_error_msg(C.errno)
		}
	}
	closed := $if windows { C._close(fd) } $else { C.close(fd) }
	if err_msg == '' && closed != 0 {
		err_msg = os.posix_get_error_msg(C.errno)
	}
	if err_msg != '' {
		return error(err_msg)
	}
}

// replace_file atomically replaces dst with src. On failure dst` is untouched.
fn replace_file(src string, dst string) ! {
	$if windows {
		src_w := src.replace('/', '\\').to_wide()
		dst_w := dst.replace('/', '\\').to_wide()
		for attempt := 1; true; attempt++ {
			if C.MoveFileExW(src_w, dst_w, C.MOVEFILE_REPLACE_EXISTING | C.MOVEFILE_WRITE_THROUGH) {
				return
			}
			code := C.GetLastError()
			transient := code == C.ERROR_ACCESS_DENIED || code == C.ERROR_SHARING_VIOLATION
			if !transient || attempt == 5 {
				return error('cannot replace ${dst}: ${os.get_error_msg(int(code))}')
			}
			C.Sleep(u32(attempt * 20))
		}
	} $else {
		if C.rename(&char(src.str), &char(dst.str)) != 0 {
			return error('cannot replace ${dst}: ${os.posix_get_error_msg(C.errno)}')
		}
	}
}
