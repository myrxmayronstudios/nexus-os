//! Chrono & Calendar Matrix Desktop Widget for MONO-OS
//! Renders a digital typographic clock and monthly calendar matrix using CP437 double lines.

use alloc::format;
use core::sync::atomic::Ordering;
use crate::arch::x86_64::interrupts::SYSTEM_TICKS;
use crate::gui::font::{FONT_HEIGHT, FONT_WIDTH};
use crate::gui::framebuffer::MonoDisplay;

pub struct ChronoWidget {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

impl ChronoWidget {
    pub const fn new(x: usize, y: usize) -> Self {
        Self {
            x,
            y,
            width: 32 * FONT_WIDTH,
            height: 12 * FONT_HEIGHT,
        }
    }

    pub fn render(&self, display: &mut MonoDisplay) {
        display.draw_double_box(self.x, self.y, self.width, self.height, Some("CHRONO MATRIX"));

        let ticks = SYSTEM_TICKS.load(Ordering::Relaxed);
        // Estimate seconds from 100Hz timer ticks
        let total_secs = (ticks / 100) + 3600 * 12 + 60 * 30; // 12:30:00 offset
        let hours = (total_secs / 3600) % 24;
        let mins = (total_secs / 60) % 60;
        let secs = total_secs % 60;

        let mut py = self.y + FONT_HEIGHT + 2;
        let px = self.x + FONT_WIDTH * 2;

        // Big Typographic Digital Clock
        let time_str = format!("  TIME: {:02}:{:02}:{:02} UTC", hours, mins, secs);
        display.draw_str(px, py, &time_str, true, Some(false));
        py += FONT_HEIGHT;

        let date_str = "  DATE: 2026-11-15 [SUN]";
        display.draw_str(px, py, date_str, true, Some(false));
        py += FONT_HEIGHT + 2;

        // Calendar Matrix Divider
        display.draw_str(self.x + FONT_WIDTH, py, "╠════════════════════════════╣", true, Some(false));
        py += FONT_HEIGHT;

        // Calendar Header
        let cal_header = "  Su  Mo  Tu  We  Th  Fr  Sa";
        display.draw_str(px, py, cal_header, true, Some(false));
        py += FONT_HEIGHT;

        // Calendar Rows for November 2026 (Starts on Sunday)
        let row1 = "   1   2   3   4   5   6   7";
        let row2 = "   8   9  10  11  12  13  14";
        let row3 = "  15  16  17  18  19  20  21";
        let row4 = "  22  23  24  25  26  27  28";
        let row5 = "  29  30";

        display.draw_str(px, py, row1, true, Some(false));
        py += FONT_HEIGHT;
        display.draw_str(px, py, row2, true, Some(false));
        py += FONT_HEIGHT;

        // Highlight current day 15 with inverted text
        display.draw_str(px, py, " ", true, Some(false));
        display.draw_str(px + FONT_WIDTH, py, "15", false, Some(true)); // Inverted
        display.draw_str(px + 3 * FONT_WIDTH, py, "  16  17  18  19  20  21", true, Some(false));
        py += FONT_HEIGHT;

        display.draw_str(px, py, row4, true, Some(false));
        py += FONT_HEIGHT;
        display.draw_str(px, py, row5, true, Some(false));
    }
}
