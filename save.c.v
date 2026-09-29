module main

import os
import rand
import strings

fn C.fsync(fd i32) i32
fn C.fchown(fd i32, owner u32, group u32) i32
fn C.fchmod(fd i32, mode u32) i32
fn C._write(fd i32, buf voidptr, count u32) i32
fn C._commit(fd i32) i32
fn C._close(fd i32) i32
fn C._open_osfhandle(handle isize, flags i32) i32
fn C.CreateFileW(name &u16, access u32, share u32, sa voidptr, disposition u32, flags u32, template voidptr) voidptr
fn C.GetFileSecurityW(name &u16, info u32, sd voidptr, len u32, needed &u32) bool
fn C.MoveFileExW(existing &u16, new &u16, flags u32) bool

// SECURITY_ATTRIBUTES
struct WinSecurityAttributes {
mut:
	length         u32
	descriptor     voidptr
	inherit_handle i32
}

// write_lines replaces the file at path by writing a new temporary file next to it
// and renaming it over the original.
fn write_lines(path string, lines []string) ! {
	// Resolve symlinks, so that the link's target is updated instead of the link
	// being replaced by a regular file.
	target := os.real_path(path)
	mut orig := ?os.Stat(none)
	if st := os.stat(target) {
		orig = st
	}
	// The copy of an existing file must never be more accessible than the original,
	// not even while it is being written: on Windows it is created with the original's
	// security descriptor, elsewhere as 0600 until it gets the original's owner and mode.
	mut sd := []u8{}
	if orig != none {
		sd = security_descriptor(target)!
	}
	perm := if orig == none { 0o666 } else { 0o600 }
	tmp, fd := create_temp_file(target, perm, sd)!
	mut sb := strings.new_builder(4096)
	for line in lines {
		sb.write_string(line)
		sb.write_u8(`\n`)
	}
	finish_temp_file(fd, tmp, sb, orig) or {
		os.rm(tmp) or {}
		return err
	}
	replace_file(tmp, target) or {
		os.rm(tmp) or {}
		return err
	}
}

// create_temp_file creates a new file next to target and returns its path and
// descriptor. The creation is exclusive: it fails instead of reusing an existing file,
// e.g. another save's temporary file or a symlink placed under the same name.
fn create_temp_file(target string, perm int, sd []u8) !(string, int) {
	dir := os.dir(target)
	name := os.file_name(target)
	for _ in 0 .. 100 {
		tmp := os.join_path(dir, '.${name}.${rand.u32():08x}.ved-tmp')
		fd := open_exclusive(tmp, perm, sd) or {
			return error('cannot create ${tmp}: ${err.msg()}')
		}
		if fd != -1 {
			return tmp, fd
		}
	}
	return error('cannot create a temporary file in ${dir}')
}

// open_exclusive creates the file at path and returns its descriptor or -1 if
// something already exists under that name.
fn open_exclusive(path string, perm int, sd []u8) !int {
	$if windows {
		mut sa := WinSecurityAttributes{
			length: u32(sizeof(WinSecurityAttributes))
		}
		if sd.len > 0 {
			sa.descriptor = sd.data
		}
		h := C.CreateFileW(path.replace('/', '\\').to_wide(), C.GENERIC_WRITE, 0, &sa,
			C.CREATE_NEW, C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
		if isize(h) == -1 {
			code := C.GetLastError()
			if code == C.ERROR_FILE_EXISTS {
				return -1
			}
			return error(os.get_error_msg(int(code)))
		}
		fd := C._open_osfhandle(isize(h), C._O_WRONLY | C._O_BINARY)
		if fd == -1 {
			C.CloseHandle(h)
			os.rm(path) or {}
			return error('cannot get a descriptor for the new file')
		}
		return fd
	} $else {
		// O_CLOEXEC keeps the descriptor out of formatter and build processes.
		fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, perm)
		if fd == -1 {
			if C.errno == C.EEXIST {
				return -1
			}
			return error(os.posix_get_error_msg(C.errno))
		}
		return fd
	}
}

// security_descriptor returns the DACL of the file at path as a self relative
// security descriptor. It's empty outside Windows.
fn security_descriptor(path string) ![]u8 {
	$if windows {
		w := path.replace('/', '\\').to_wide()
		info := u32(C.DACL_SECURITY_INFORMATION)
		mut needed := u32(0)
		C.GetFileSecurityW(w, info, unsafe { nil }, 0, &needed)
		if needed > 0 {
			mut sd := []u8{len: int(needed)}
			if C.GetFileSecurityW(w, info, sd.data, needed, &needed) {
				return sd
			}
		}
		return error('cannot read the permissions of ${path}: ${os.get_error_msg(int(C.GetLastError()))}')
	} $else {
		return []u8{}
	}
}

// finish_temp_file writes data to the new file, gives it the original's owner, group
// and mode, flushes it to disk and closes it. fd is closed in every case.
fn finish_temp_file(fd int, tmp string, data []u8, orig ?os.Stat) ! {
	fill_temp_file(fd, tmp, data, orig) or {
		close_fd(fd)
		return err
	}
	if close_fd(fd) != 0 {
		return error(os.posix_get_error_msg(C.errno))
	}
}

fn fill_temp_file(fd int, tmp string, data []u8, orig ?os.Stat) ! {
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
			return error(os.posix_get_error_msg(C.errno))
		}
		written += n
	}
	$if !windows {
		if st := orig {
			now := os.stat(tmp)!
			if (now.uid != st.uid || now.gid != st.gid) && C.fchown(fd, st.uid, st.gid) != 0 {
				return error('cannot keep the owner and group of the file: ${os.posix_get_error_msg(C.errno)}')
			}
			if C.fchmod(fd, st.mode & 0o7777) != 0 {
				return error('cannot keep the mode of the file: ${os.posix_get_error_msg(C.errno)}')
			}
		}
	}
	synced := $if windows { C._commit(fd) } $else { C.fsync(fd) }
	if synced != 0 {
		return error(os.posix_get_error_msg(C.errno))
	}
}

fn close_fd(fd int) int {
	return $if windows { C._close(fd) } $else { C.close(fd) }
}

// replace_file atomically replaces dst with src. On failure dst is untouched.
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
