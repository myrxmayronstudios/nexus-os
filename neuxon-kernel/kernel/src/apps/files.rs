//! NeuxonFiles: Graphical Dual-Pane Tree File Explorer for Neuxon OS
//! Renders hierarchical directory trees (├─, └─) and file attribute tables using CP437 box glyphs.

use alloc::format;
use crate::gui::font::{FONT_HEIGHT, FONT_WIDTH};
use crate::gui::framebuffer::MonoDisplay;
use crate::gui::wm::WindowManager;

pub fn launch(wm: &mut WindowManager) {
    wm.spawn_window(
        "NeuxonFiles [Dual-Pane VFS Explorer]",
        "files",
        120,
        50,
        620,
        380,
        |display, cx, cy, cw, ch| {
        let pane_w = cw / 3;

        // Draw Vertical Divider between panes
        for py in cy..(cy + ch) {
            display.draw_char(cx + pane_w, py, '│', true, Some(false));
        }

        // Left Pane: Directory Tree
        let mut tree_y = cy;
        let left_x = cx;
        display.draw_str(left_x, tree_y, "DIRECTORIES", false, Some(true)); // Inverted Header
        tree_y += FONT_HEIGHT + 4;

        let tree_nodes = [
            "/ (root)",
            "├─ 📁 sys/",
            "│  ├─ version",
            "│  ├─ cmdline",
            "│  └─ notes.txt",
            "├─ 📁 dev/",
            "│  ├─ fb0",
            "│  ├─ ttyS0",
            "│  └─ ring0",
            "├─ 📁 home/",
            "│  └─ 📁 user/",
            "│     └─ welcome.txt",
            "└─ 📁 etc/",
            "   └─ mono.conf",
        ];

        for node in tree_nodes.iter() {
            if tree_y + FONT_HEIGHT > cy + ch {
                break;
            }
            display.draw_str(left_x, tree_y, node, true, Some(false));
            tree_y += FONT_HEIGHT;
        }

        // Right Pane: File Attribute Table
        let right_x = cx + pane_w + FONT_WIDTH;
        let mut table_y = cy;

        // Table Header
        let header = "NAME              SIZE       PERM        TYPE";
        display.draw_str(right_x, table_y, header, false, Some(true));
        table_y += FONT_HEIGHT + 4;

        let files = [
            ("..",                 "<DIR>",   "rwxr-xr-x", "Parent Directory"),
            ("version",            "48 B",    "rw-r--r--", "Kernel Info"),
            ("kernel_cmdline",     "68 B",    "rw-r--r--", "Boot Arguments"),
            ("notes.txt",          "156 B",   "rw-rw-r--", "Plaintext Note"),
            ("fb0",                "3.0 MB",  "rw-rw----", "Linear Framebuffer"),
            ("ttyS0",              "0 B",     "rw-rw----", "16550 UART Serial"),
            ("ring0",              "16 KB",   "rw-rw-rw-", "Shared Syscall Ring"),
            ("welcome.txt",        "64 B",    "rw-r--r--", "Plaintext Document"),
            ("mono.conf",          "210 B",   "rw-r--r--", "Configuration"),
        ];

        for (name, size, perm, ftype) in files.iter() {
            if table_y + FONT_HEIGHT > cy + ch {
                break;
            }
            let line = format!("{:<17} {:<10} {:<11} {}", name, size, perm, ftype);
            display.draw_str(right_x, table_y, &line, true, Some(false));
            table_y += FONT_HEIGHT;
        }

        // Bottom status line
        let status = "8 objects, 3.01 MB total | VFS Driver: In-Memory /sys";
        display.draw_str(cx, cy + ch.saturating_sub(FONT_HEIGHT), status, true, Some(false));
    });
}
