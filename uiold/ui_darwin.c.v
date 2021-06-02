module uiold

#flag -framework Carbon
#flag -framework Cocoa

#include <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>

#include "@VROOT/uiold/uiold.m"

struct C.NSFont {}

fn C.reg_key_ved2()

pub fn reg_key_ved() {
	C.reg_key_ved2()
}
