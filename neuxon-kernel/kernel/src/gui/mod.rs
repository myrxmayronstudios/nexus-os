//! MonoWM: 1-Bit Monochrome & Character-Punk Graphical Compositor Subsystem

pub mod dither;
pub mod font;
pub mod framebuffer;
pub mod widgets;
pub mod wm;

use bootloader::bootinfo::FrameBuffer;

/// Initialize the complete GUI subsystem (Framebuffer, Font, Desktop Widgets, WM)
pub fn init(hw_fb: &'static mut FrameBuffer) {
    framebuffer::init(hw_fb);
    let display_lock = framebuffer::DISPLAY.lock();
    if let Some(ref display) = *display_lock {
        let (w, h) = (display.width(), display.height());
        drop(display_lock);
        wm::init(w, h);
    }
}
