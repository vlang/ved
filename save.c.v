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
fn C.ReplaceFileW(replaced &u16, replacement &u16, backup &u16, flags u32, exclude voidptr, reserved voidptr) bool
fn C.FlushFileBuffers(h voidptr) bool
fn C.GetFileInformationByHandle(h voidptr, info &C.BY_HANDLE_FILE_INFORMATION) bool

$if macos {
	#include <copyfile.h>
	#include <sys/acl.h>
}
$if linux {
	#include <sys/xattr.h>
	#include <sys/ioctl.h>
	#include <linux/fs.h>
}

fn C.ioctl(fd i32, request u64, args ...voidptr) i32
fn C.fstat(fd i32, buf voidptr) i32
fn C.fchflags(fd i32, flags u32) i32

fn C.copyfile(from &char, to &char, state voidptr, flags u32) i32
fn C.listxattr(path &char, list &char, size usize) isize
fn C.getxattr(path &char, name &char, value voidptr, size usize) isize
fn C.fgetxattr(fd i32, name &char, value voidptr, size usize) isize
fn C.fsetxattr(fd i32, name &char, value voidptr, size usize, flags i32) i32
fn C.flistxattr(fd i32, list &char, size usize) isize
fn C.fremovexattr(fd i32, name &char) i32
fn C.acl_init(count i32) voidptr
fn C.acl_set_fd(fd i32, acl voidptr) i32
fn C.acl_free(obj voidptr) i32

struct C.fsxattr {
mut:
	fsx_xflags     u32
	fsx_extsize    u32
	fsx_nextents   u32
	fsx_projid     u32
	fsx_cowextsize u32
}

@[typedef]
struct C.BY_HANDLE_FILE_INFORMATION {
	nNumberOfLinks u32
}

struct WinSecurityAttributes {
mut:
	length         u32
	descriptor     voidptr
	inherit_handle i32
}

fn load_lines(path string) ![]string {
	return os.read_lines(path) or {
		os.stat(path) or {
			if err.code() == C.ENOENT {
				return []string{}
			}
			return err
		}
		return err
	}
}

// write_lines writes lines directly into the file at path.
fn write_lines(path string, lines []string) ! {
	mut file := os.create(path)!
	defer {
		file.close()
	}
	for line in lines {
		file.writeln(line)!
	}
}

// write_lines_atomic writes lines to a temporary file and replaces the file at path with it.
fn write_lines_atomic(path string, lines []string) ! {
	target := resolve_links(path) or { return error('cannot resolve ${path}: ${err.msg()}') }
	mut orig := ?os.Stat(none)
	if st := os.stat(target) {
		orig = st
	} else {
		if err.code() != C.ENOENT {
			return error('cannot read ${path}: ${err.msg()}')
		}
	}
	if orig != none && !can_write(target) {
		return error('${path} is read-only')
	}
	if st := orig {
		if st.get_filetype() != .regular {
			return error('${path} is not a regular file, only regular files can be saved atomically')
		}
		if link_count(target, st) > 1 {
			return error('${path} has other hard links, saving would separate them')
		}
	}
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
	finish_temp_file(fd, tmp, target, sb, orig) or {
		os.rm(tmp) or {}
		return err
	}
	replace_file(tmp, target, orig != none)!
}

// resolve_links follows symlinks at path, also to a file that doesn't exist yet.
fn resolve_links(path string) !string {
	resolved := os.real_path(path)
	if os.exists(resolved) {
		return resolved
	}
	mut p := path
	for _ in 0 .. 40 {
		if !os.is_link(p) {
			return p
		}
		link := os.readlink(p)!
		p = if os.is_abs_path(link) { link } else { os.join_path(os.dir(p), link) }
	}
	return error('too many levels of symbolic links')
}

// link_count returns the number of hard links of the file at path.
fn link_count(path string, st os.Stat) u64 {
	$if windows {
		share := u32(C.FILE_SHARE_READ | C.FILE_SHARE_WRITE | C.FILE_SHARE_DELETE)
		h := C.CreateFileW(path.replace('/', '\\').to_wide(), 0, share, unsafe { nil },
			C.OPEN_EXISTING, C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
		if isize(h) == -1 {
			return 1
		}
		mut info := C.BY_HANDLE_FILE_INFORMATION{}
		ok := C.GetFileInformationByHandle(h, &info)
		C.CloseHandle(h)
		return if ok { u64(info.nNumberOfLinks) } else { 1 }
	} $else {
		return st.nlink
	}
}

// can_write reports whether the file at path is writable.
fn can_write(path string) bool {
	$if windows {
		share := u32(C.FILE_SHARE_READ | C.FILE_SHARE_WRITE | C.FILE_SHARE_DELETE)
		h := C.CreateFileW(path.replace('/', '\\').to_wide(), C.FILE_WRITE_DATA, share,
			unsafe { nil }, C.OPEN_EXISTING, C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
		if isize(h) == -1 {
			return C.GetLastError() == C.ERROR_SHARING_VIOLATION
		}
		C.CloseHandle(h)
		return true
	} $else {
		return os.is_writable(path)
	}
}

// create_temp_file exclusively creates a temporary file next to target.
fn create_temp_file(target string, perm int, sd []u8) !(string, int) {
	dir := os.dir(target)
	mut attrs := u32(0)
	$if windows {
		a := C.GetFileAttributesW(&u8(target.replace('/', '\\').to_wide()))
		if a != C.INVALID_FILE_ATTRIBUTES && a & C.FILE_ATTRIBUTE_ENCRYPTED != 0 {
			attrs = C.FILE_ATTRIBUTE_ENCRYPTED
		}
	}
	for _ in 0 .. 100 {
		tmp := os.join_path(dir, '.ved-${rand.u64():016x}.ved-tmp')
		fd := open_exclusive(tmp, perm, sd, attrs) or {
			return error('cannot create ${tmp}: ${err.msg()}')
		}
		if fd != -1 {
			return tmp, fd
		}
	}
	return error('cannot create a temporary file in ${dir}')
}

// open_exclusive creates the file at path, or returns -1 if it already exists.
fn open_exclusive(path string, perm int, sd []u8, attrs u32) !int {
	$if windows {
		mut sa := WinSecurityAttributes{
			length: u32(sizeof(WinSecurityAttributes))
		}
		if sd.len > 0 {
			sa.descriptor = sd.data
		}
		h := C.CreateFileW(path.replace('/', '\\').to_wide(), C.GENERIC_WRITE, 0, &sa,
			C.CREATE_NEW, if attrs != 0 { attrs } else { u32(C.FILE_ATTRIBUTE_NORMAL) }, unsafe { nil })
		if isize(h) == -1 {
			code := C.GetLastError()
			if code == C.ERROR_FILE_EXISTS {
				return -1
			}
			if code == C.ERROR_INVALID_OWNER || code == C.ERROR_INVALID_PRIMARY_GROUP {
				return error('cannot keep the owner of the file')
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

// security_descriptor returns the owner, group and DACL of the file at path (Windows only).
fn security_descriptor(path string) ![]u8 {
	$if windows {
		w := path.replace('/', '\\').to_wide()
		info := u32(C.OWNER_SECURITY_INFORMATION | C.GROUP_SECURITY_INFORMATION | C.DACL_SECURITY_INFORMATION)
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

// finish_temp_file writes data and the original's metadata to the temporary file and closes it.
fn finish_temp_file(fd int, tmp string, target string, data []u8, orig ?os.Stat) ! {
	fill_temp_file(fd, tmp, target, data, orig) or {
		close_fd(fd)
		return err
	}
	if close_fd(fd) != 0 {
		return error(os.posix_get_error_msg(C.errno))
	}
}

fn fill_temp_file(fd int, tmp string, target string, data []u8, orig ?os.Stat) ! {
	$if linux || macos {
		if orig != none {
			copy_file_flags(target, fd)!
		}
	}
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
			copy_xattrs(target, tmp, fd)!
			mut mode := st.mode & 0o7777 & ~u32(0o4000)
			if mode & 0o010 != 0 {
				mode &= ~u32(0o2000)
			}
			if C.fchmod(fd, mode) != 0 {
				return error('cannot keep the mode of the file: ${os.posix_get_error_msg(C.errno)}')
			}
		}
	}
	if sync_fd(fd) != 0 {
		return error(os.posix_get_error_msg(C.errno))
	}
}

// The kernel drops or recomputes these on a normal write, so they aren't copied.
const rewritten_xattrs = ['security.capability', 'security.ima', 'security.evm']

// copy_xattrs copies the extended attributes (and ACLs) of target to the temporary file.
fn copy_xattrs(target string, tmp string, fd int) ! {
	$if linux {
		names := xattr_names(target, -1) or {
			return error('cannot read the extended attributes of the file: ${err.msg()}')
		}
		tmp_names := xattr_names('', fd) or {
			return error('cannot read the extended attributes of the new file: ${err.msg()}')
		}
		for name in tmp_names {
			if name in rewritten_xattrs {
				continue
			}
			if name !in names && C.fremovexattr(fd, &char(name.str)) != 0 {
				return error('cannot remove the extended attribute ${name}: ${os.posix_get_error_msg(C.errno)}')
			}
		}
		for name in names {
			if name in rewritten_xattrs {
				continue
			}
			value := read_xattr(target, -1, name) or {
				return error('cannot read the extended attribute ${name}: ${err.msg()}')
			}
			if current := read_xattr('', fd, name) {
				if current == value {
					continue
				}
			}
			if C.fsetxattr(fd, &char(name.str), value.data, usize(value.len), 0) != 0 {
				return error('cannot keep the extended attribute ${name}: ${os.posix_get_error_msg(C.errno)}')
			}
		}
	} $else $if macos {
		empty := C.acl_init(0)
		cleared := C.acl_set_fd(fd, empty)
		C.acl_free(empty)
		if cleared != 0 {
			return error('cannot clear the ACL of the new file: ${os.posix_get_error_msg(C.errno)}')
		}
		if C.copyfile(&char(target.str), &char(tmp.str), unsafe { nil }, C.COPYFILE_ACL | C.COPYFILE_XATTR) != 0 {
			return error('cannot keep the ACL and extended attributes of the file: ${os.posix_get_error_msg(C.errno)}')
		}
	}
}

// xattr_names lists the extended attributes of path, or of fd when fd is not -1.
fn xattr_names(path string, fd int) ![]string {
	$if linux {
		size := if fd == -1 {
			C.listxattr(&char(path.str), unsafe { nil }, 0)
		} else {
			C.flistxattr(fd, unsafe { nil }, 0)
		}
		if size < 0 {
			if C.errno == C.ENOTSUP {
				return []string{}
			}
			return error(os.posix_get_error_msg(C.errno))
		}
		if size == 0 {
			return []string{}
		}
		mut list := []u8{len: int(size)}
		n := if fd == -1 {
			C.listxattr(&char(path.str), &char(list.data), usize(list.len))
		} else {
			C.flistxattr(fd, &char(list.data), usize(list.len))
		}
		if n < 0 {
			return error(os.posix_get_error_msg(C.errno))
		}
		return list[..n].bytestr().split('\0').filter(it != '')
	} $else {
		return []string{}
	}
}

// copy_file_flags copies the file flags of target (chattr, chflags) to the temporary file.
fn copy_file_flags(target string, fd int) ! {
	$if linux {
		src := C.open(&char(target.str), C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC)
		if src == -1 {
			return error('cannot read the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
		mut flags := i32(0)
		got := C.ioctl(src, C.FS_IOC_GETFLAGS, &flags)
		code := C.errno
		mut fsx := C.fsxattr{}
		got_fsx := C.ioctl(src, C.FS_IOC_FSGETXATTR, &fsx)
		C.close(src)
		if got != 0 {
			if code == C.ENOTTY || code == C.EOPNOTSUPP || code == C.EINVAL {
				return
			}
			return error('cannot read the file flags: ${os.posix_get_error_msg(code)}')
		}
		if flags & C.FS_VERITY_FL != 0 {
			return error('the file is protected by fs-verity')
		}
		mask := i32((C.FS_FL_USER_MODIFIABLE | C.FS_NOCOMP_FL | C.FS_NOCOW_FL | C.FS_DAX_FL | C.FS_JOURNAL_DATA_FL) & ~(C.FS_IMMUTABLE_FL | C.FS_APPEND_FL))
		mut tmp_flags := i32(0)
		if C.ioctl(fd, C.FS_IOC_GETFLAGS, &tmp_flags) != 0 {
			if flags & mask == 0 {
				return
			}
			return error('cannot keep the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
		mut want := (tmp_flags & ~mask) | (flags & mask)
		if want != tmp_flags && C.ioctl(fd, C.FS_IOC_SETFLAGS, &want) != 0 {
			return error('cannot keep the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
		mut tmp_fsx := C.fsxattr{}
		if got_fsx == 0 && C.ioctl(fd, C.FS_IOC_FSGETXATTR, &tmp_fsx) == 0 {
			xmask := u32(C.FS_XFLAG_REALTIME | C.FS_XFLAG_EXTSIZE | C.FS_XFLAG_COWEXTSIZE | C.FS_XFLAG_NODEFRAG | C.FS_XFLAG_FILESTREAM)
			mut want_fsx := tmp_fsx
			want_fsx.fsx_xflags = (tmp_fsx.fsx_xflags & ~xmask) | (fsx.fsx_xflags & xmask)
			want_fsx.fsx_extsize = fsx.fsx_extsize
			want_fsx.fsx_cowextsize = fsx.fsx_cowextsize
			want_fsx.fsx_projid = fsx.fsx_projid
			changed := want_fsx.fsx_xflags != tmp_fsx.fsx_xflags
				|| want_fsx.fsx_extsize != tmp_fsx.fsx_extsize
				|| want_fsx.fsx_cowextsize != tmp_fsx.fsx_cowextsize
				|| want_fsx.fsx_projid != tmp_fsx.fsx_projid
			if changed && C.ioctl(fd, C.FS_IOC_FSSETXATTR, &want_fsx) != 0 {
				return error('cannot keep the project ID and allocation settings of the file: ${os.posix_get_error_msg(C.errno)}')
			}
		}
	} $else $if macos {
		mut s := C.stat{}
		if C.stat(&char(target.str), &s) != 0 {
			return error('cannot read the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
		mut t := C.stat{}
		if C.fstat(fd, &t) != 0 {
			return error('cannot read the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
		mask := u32((C.UF_SETTABLE | C.SF_SETTABLE) & ~(C.UF_IMMUTABLE | C.UF_APPEND | C.UF_COMPRESSED | C.SF_IMMUTABLE | C.SF_APPEND))
		want := (t.st_flags & ~mask) | (s.st_flags & mask)
		if want != t.st_flags && C.fchflags(fd, want) != 0 {
			return error('cannot keep the file flags: ${os.posix_get_error_msg(C.errno)}')
		}
	}
}

// read_xattr returns an extended attribute of path, or of fd when fd is not -1.
fn read_xattr(path string, fd int, name string) ![]u8 {
	$if linux {
		size := if fd == -1 {
			C.getxattr(&char(path.str), &char(name.str), unsafe { nil }, 0)
		} else {
			C.fgetxattr(fd, &char(name.str), unsafe { nil }, 0)
		}
		if size < 0 {
			return error(os.posix_get_error_msg(C.errno))
		}
		mut value := []u8{len: int(size)}
		if size == 0 {
			return value
		}
		got := if fd == -1 {
			C.getxattr(&char(path.str), &char(name.str), value.data, usize(value.len))
		} else {
			C.fgetxattr(fd, &char(name.str), value.data, usize(value.len))
		}
		if got < 0 {
			return error(os.posix_get_error_msg(C.errno))
		}
		return value[..got]
	} $else {
		return []u8{}
	}
}

// sync_fd flushes the file to stable storage.
fn sync_fd(fd int) int {
	$if windows {
		return C._commit(fd)
	} $else $if macos {
		if C.fcntl(fd, C.F_FULLFSYNC) == 0 {
			return 0
		}
		return C.fsync(fd)
	} $else {
		return C.fsync(fd)
	}
}

fn close_fd(fd int) int {
	return $if windows { C._close(fd) } $else { C.close(fd) }
}

// replace_file atomically replaces dst with src.
fn replace_file(src string, dst string, existing bool) ! {
	$if windows {
		src_w := src.replace('/', '\\').to_wide()
		dst_w := dst.replace('/', '\\').to_wide()
		for attempt := 1; true; attempt++ {
			ok := if existing {
				C.ReplaceFileW(dst_w, src_w, unsafe { nil }, 0, unsafe { nil }, unsafe { nil })
			} else {
				C.MoveFileExW(src_w, dst_w, C.MOVEFILE_REPLACE_EXISTING | C.MOVEFILE_WRITE_THROUGH)
			}
			if ok {
				break
			}
			code := C.GetLastError()
			if code == C.ERROR_UNABLE_TO_MOVE_REPLACEMENT
				|| code == C.ERROR_UNABLE_TO_MOVE_REPLACEMENT_2 {
				if C.MoveFileExW(src_w, dst_w, C.MOVEFILE_REPLACE_EXISTING | C.MOVEFILE_WRITE_THROUGH) {
					break
				}
				return error('cannot replace ${dst}, the new contents are in ${src}: ${os.get_error_msg(int(C.GetLastError()))}')
			}
			transient := code == C.ERROR_ACCESS_DENIED || code == C.ERROR_SHARING_VIOLATION
				|| code == C.ERROR_UNABLE_TO_REMOVE_REPLACED
			if !transient || attempt == 5 {
				os.rm(src) or {}
				return error('cannot replace ${dst}: ${os.get_error_msg(int(code))}')
			}
			C.Sleep(u32(attempt * 20))
		}
		if existing {
			flush_file(dst) or {
				return error('${dst} was saved, but may not survive a crash: ${err.msg()}')
			}
		}
	} $else {
		if C.rename(&char(src.str), &char(dst.str)) != 0 {
			os.rm(src) or {}
			return error('cannot replace ${dst}: ${os.posix_get_error_msg(C.errno)}')
		}
		sync_dir(os.dir(dst)) or {
			return error('${dst} was saved, but may not survive a crash: ${err.msg()}')
		}
	}
}

// flush_file flushes the file at path to disk (Windows only).
fn flush_file(path string) ! {
	$if windows {
		share := u32(C.FILE_SHARE_READ | C.FILE_SHARE_WRITE | C.FILE_SHARE_DELETE)
		h := C.CreateFileW(path.replace('/', '\\').to_wide(), C.GENERIC_WRITE, share, unsafe { nil },
			C.OPEN_EXISTING, C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
		if isize(h) == -1 {
			return error(os.get_error_msg(int(C.GetLastError())))
		}
		flushed := C.FlushFileBuffers(h)
		code := C.GetLastError()
		C.CloseHandle(h)
		if !flushed {
			return error(os.get_error_msg(int(code)))
		}
	}
}

// sync_dir flushes the directory dir to disk.
fn sync_dir(dir string) ! {
	$if !windows {
		fd := C.open(&char(dir.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		if fd == -1 {
			return error(os.posix_get_error_msg(C.errno))
		}
		synced := C.fsync(fd)
		code := C.errno
		C.close(fd)
		if synced != 0 && code != C.EINVAL {
			return error(os.posix_get_error_msg(code))
		}
	}
}
