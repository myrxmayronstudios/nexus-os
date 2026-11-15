//! VFS Sticky Pad Desktop Widget for MONO-OS
//! Displays persistent desktop notes backed directly by the kernel Virtual File System (/sys/notes.txt).

use alloc::string::String;
use crate::gui::font::{FONT_HEIGHT, FONT_WIDTH};
use crate::gui::framebuffer::MonoDisplay;
use crate::vfs;

pub struct StickyPadWidget {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

impl StickyPadWidget {
    pub const fn new(x: usize, y: usize) -> Self {
        Self {
            x,
            y,
            width: 44 * FONT_WIDTH,
            height: 9 * FONT_HEIGHT,
        }
    }

    pub fn render(&self, display: &mut MonoDisplay) {
        display.draw_double_box(self.x, self.y, self.width, self.height, Some("VFS STICKY PAD [/sys/notes.txt]"));

        let content_bytes = vfs::read("/sys/notes.txt").unwrap_or_else(|| {
            alloc::vec::Vec::from(b"No notes available.".as_slice())
        });

        let content_str = String::from_utf8_lossy(&content_bytes);
        let mut py = self.y + FONT_HEIGHT + 2;
        let px = self.x + FONT_WIDTH;

        let max_lines = (self.height / FONT_HEIGHT).saturating_sub(2);
        for (i, line) in content_str.lines().enumerate() {
            if i >= max_lines {
                break;
            }
            display.draw_str(px, py, line, true, Some(false));
            py += FONT_HEIGHT;
        }
    }
}
