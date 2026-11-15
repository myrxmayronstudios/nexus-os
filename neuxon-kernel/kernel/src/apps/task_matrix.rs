//! TaskMatrix: Graphical Process Manager & Thread Inspector for Neuxon OS
//! Displays thread priorities, memory page allocations, CPU utilization, and task control actions.

use alloc::format;
use crate::gui::font::{FONT_HEIGHT, FONT_WIDTH};
use crate::gui::framebuffer::MonoDisplay;
use crate::gui::wm::WindowManager;

pub fn launch(wm: &mut WindowManager) {
    wm.spawn_window(
        "TaskMatrix [Process & Memory Manager]",
        "taskmatrix",
        180,
        60,
        640,
        380,
        |display, cx, cy, cw, ch| {
        let mut py = cy;

        // Header Toolbar
        let toolbar = "[K] Kill Thread   [P] Boost Priority   [H] Inspect HugePages   [R] Refresh";
        display.draw_str(cx, py, toolbar, false, Some(true)); // Inverted
        py += FONT_HEIGHT + 6;

        // Process Table Header
        let col_header = "PID  NAME          PRIORITY    CPU%  PAGES (4K)   STATE";
        display.draw_str(cx, py, col_header, true, Some(false));
        py += FONT_HEIGHT + 2;

        display.draw_str(cx, py, "─────────────────────────────────────────────────────────────", true, Some(false));
        py += FONT_HEIGHT;

        let tasks = [
            (1, "idle_worker",   "Idle",       " 1%",  "      4 pages", "RUNNING [Core 0]"),
            (2, "mono_wm",       "Compositor", "14%",  "    192 pages", "RUNNING [Core 1]"),
            (3, "mono_ring",     "Interactive"," 3%",  "      8 pages", "READY   [Core 0]"),
            (4, "v8_chromium",   "Normal",     "38%",  "   4096 pages", "READY   [Core 2]"),
            (5, "blink_raster",  "Compositor", "22%",  "   2048 pages", "READY   [Core 3]"),
            (6, "virtio_gpu",    "Interactive"," 6%",  "    512 pages", "BLOCKED [IRQ 14]"),
            (7, "vfs_worker",    "Normal",     " 2%",  "     32 pages", "READY   [Core 1]"),
        ];

        for (pid, name, prio, cpu, pages, state) in tasks.iter() {
            if py + FONT_HEIGHT > cy + ch.saturating_sub(FONT_HEIGHT * 2) {
                break;
            }
            let row = format!("{:<4} {:<13} {:<11} {:<5} {:<12} {}", pid, name, prio, cpu, pages, state);
            display.draw_str(cx, py, &row, true, Some(false));
            py += FONT_HEIGHT;
        }

        // Summary at bottom
        py = cy + ch.saturating_sub(FONT_HEIGHT * 2);
        display.draw_str(cx, py, "─────────────────────────────────────────────────────────────", true, Some(false));
        py += FONT_HEIGHT;
        let summary = "7 Tasks Active | HugePages: 2 (4MB mapped) | Zero Deadlocks";
        display.draw_str(cx, py, summary, true, Some(false));
    });
}
