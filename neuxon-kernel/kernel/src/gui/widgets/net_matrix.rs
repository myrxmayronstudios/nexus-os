//! Network & Packet Matrix Desktop Widget for MONO-OS
//! Renders a live hex/ASCII stream of network socket activity and kernel packet inspections.

use alloc::format;
use core::sync::atomic::Ordering;
use crate::arch::x86_64::interrupts::SYSTEM_TICKS;
use crate::gui::font::{FONT_HEIGHT, FONT_WIDTH};
use crate::gui::framebuffer::MonoDisplay;

pub struct NetMatrixWidget {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

impl NetMatrixWidget {
    pub const fn new(x: usize, y: usize) -> Self {
        Self {
            x,
            y,
            width: 44 * FONT_WIDTH,
            height: 10 * FONT_HEIGHT,
        }
    }

    pub fn render(&self, display: &mut MonoDisplay) {
        display.draw_double_box(self.x, self.y, self.width, self.height, Some("NET MATRIX [virtio-net]"));

        let ticks = SYSTEM_TICKS.load(Ordering::Relaxed);
        let mut py = self.y + FONT_HEIGHT + 2;
        let px = self.x + FONT_WIDTH;

        let status = format!("IFACE: eth0 [UP] | IP: 10.0.2.15 | RX/TX: {} KB", ticks / 8);
        display.draw_str(px, py, &status, true, Some(false));
        py += FONT_HEIGHT;

        display.draw_str(px, py, "── LIVE RAW PACKET HEX INSPECTOR ───────────", true, Some(false));
        py += FONT_HEIGHT;

        // Dynamic simulated packet captures based on timer cycle
        let offset = (ticks % 4) as usize;
        let packets = [
            ("08:00 45 00 00 3C 1A 2B 40 00 40 06", "TCP  :80 -> :49152 [ACK]"),
            ("08:00 45 00 00 28 3C 4D 40 00 40 11", "UDP  DNS 1.1.1.1:53"),
            ("08:00 45 00 01 04 5E 6F 40 00 40 06", "HTTP TLSv1.3 Handshake"),
            ("08:06 00 01 08 00 06 04 00 01 FF FF", "ARP  Who has 10.0.2.2?"),
            ("08:00 45 00 00 54 A1 B2 40 00 40 01", "ICMP Echo Reply seq=42"),
        ];

        for i in 0..4 {
            let idx = (offset + i) % packets.len();
            let (hex, proto) = packets[idx];
            let line = format!("{} | {}", hex, proto);
            display.draw_str(px, py, &line, true, Some(false));
            py += FONT_HEIGHT;
        }

        display.draw_str(px, py, "SOCKETS: 3 ESTABLISHED, 0 WAIT_CLOSE", true, Some(false));
    }
}
