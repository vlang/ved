module main

fn test_save_native_word_types_keep_width_and_signedness() {
	assert sizeof(C.size_t) == sizeof(voidptr)
	assert sizeof(C.intptr_t) == sizeof(voidptr)
	// Exercise values above the 32-bit range on 64-bit hosts without overflowing
	// the native word on 32-bit hosts.
	wide := uint(1) << (sizeof(voidptr) * 8 - 2)
	assert uint(C.size_t(wide)) == wide
	assert int(C.intptr_t(-1)) == -1
	value := u8(7)
	handle := voidptr(&value)
	assert voidptr(C.intptr_t(handle)) == handle
	$if linux {
		assert sizeof(C.ssize_t) == sizeof(voidptr)
		assert int(C.ssize_t(-1)) == -1
	}
}
