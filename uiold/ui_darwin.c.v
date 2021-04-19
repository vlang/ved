module uiold

#flag -framework Carbon
#flag -framework Cocoa

#include <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>

#include "@VROOT/uiold/uiold.m"

struct C.NSFont {}

__global default_font &C.NSFont

fn C.reg_key_vid2()

pub fn reg_key_vid() {
	C.reg_key_vid2()
}
