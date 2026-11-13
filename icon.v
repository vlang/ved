module main

import stbi
import sokol.sapp

const icon_png = $embed_file('assets/v_icon.png')

// app_icon decodes the embedded V logo into the RGBA pixels sokol needs for the window icon.
// The decoded image is not freed on purpose, sokol may read it after the window is created.
fn app_icon() sapp.IconDesc {
	img := stbi.load_from_memory(icon_png.data(), icon_png.len, desired_channels: 4) or {
		return sapp.IconDesc{
			sokol_default: true
		}
	}
	mut icon := sapp.IconDesc{}
	icon.images[0] = sapp.ImageDesc{
		width:  img.width
		height: img.height
		pixels: sapp.Range{
			ptr:  img.data
			size: usize(img.width * img.height * 4)
		}
	}
	return icon
}
