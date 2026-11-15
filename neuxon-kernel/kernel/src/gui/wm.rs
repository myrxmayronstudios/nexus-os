//! NeuxonWM: macOS-Style 1-Bit Monochrome & Character-Punk Window Manager & Display Server
//! Implements a Global Top Menu Bar, Centered Floating macOS Character Dock with Hover Magnification,
//! Top-Left Character Traffic Lights ([ ✕ ][ − ][ + ]), Active Process Indicators, and Window Snapping.

use alloc::boxed::Box;
use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use spin::Mutex;

use super::dither::ShadingPattern;
use super::font::{FONT_HEIGHT, FONT_WIDTH};
use super::framebuffer::MonoDisplay;
use super::widgets::WidgetManager;
use crate::drivers::keyboard::{KeyCode, KeyEvent, KeyState};
use crate::drivers::mouse::{MouseButtons, MouseState};

pub const TOP_MENUBAR_HEIGHT: usize = 22;
pub const DOCK_HEIGHT: usize = 42;
pub const DOCK_BOTTOM_MARGIN: usize = 8;
pub const DOCK_ITEM_WIDTH: usize = 48;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowState {
    Normal,
    Maximized,
    Minimized,
    SnappedLeft,
    SnappedRight,
}

pub type WindowRenderCallback = Box<dyn FnMut(&mut MonoDisplay, usize, usize, usize, usize) + Send>;

pub struct Window {
    pub id: usize,
    pub title: String,
    pub app_type: String, // "terminal", "browser", "files", "taskmatrix", "notes"
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
    pub saved_x: usize,
    pub saved_y: usize,
    pub saved_width: usize,
    pub saved_height: usize,
    pub state: WindowState,
    pub is_focused: bool,
    pub is_draggable: bool,
    pub is_resizable: bool,
    pub render_content: WindowRenderCallback,
}

pub struct DockItem {
    pub app_type: &'static str,
    pub label: &'static str,
    pub glyph: &'static str,
    pub is_pinned: bool,
}

pub struct WindowManager {
    pub windows: Vec<Window>,
    pub next_window_id: usize,
    pub focused_window_id: Option<usize>,
    pub screen_width: usize,
    pub screen_height: usize,
    pub dragging_window_id: Option<usize>,
    pub drag_offset_x: usize,
    pub drag_offset_y: usize,
    pub apple_menu_open: bool,
    pub widgets: WidgetManager,
    pub hovered_dock_index: Option<usize>,
    pub dock_items: Vec<DockItem>,
}

impl WindowManager {
    pub fn new(screen_width: usize, screen_height: usize) -> Self {
        let widgets = WidgetManager::new(screen_width, screen_height);

        let dock_items = alloc::vec![
            DockItem { app_type: "browser",    label: "Chromium",   glyph: "🌐", is_pinned: true },
            DockItem { app_type: "terminal",   label: "NeuxonTerm", glyph: ">_", is_pinned: true },
            DockItem { app_type: "files",      label: "NeuxonFiles",glyph: "📁", is_pinned: true },
            DockItem { app_type: "taskmatrix", label: "TaskMatrix", glyph: "📊", is_pinned: true },
            DockItem { app_type: "notes",      label: "Notes",      glyph: "📝", is_pinned: true },
            DockItem { app_type: "trash",      label: "Trash",      glyph: "🗑", is_pinned: true },
        ];

        Self {
            windows: Vec::new(),
            next_window_id: 1,
            focused_window_id: None,
            screen_width,
            screen_height,
            dragging_window_id: None,
            drag_offset_x: 0,
            drag_offset_y: 0,
            apple_menu_open: false,
            widgets,
            hovered_dock_index: None,
            dock_items,
        }
    }

    pub fn spawn_window<F>(
        &mut self,
        title: &str,
        app_type: &str,
        x: usize,
        y: usize,
        width: usize,
        height: usize,
        render_content: F,
    ) -> usize
    where
        F: FnMut(&mut MonoDisplay, usize, usize, usize, usize) + Send + 'static,
    {
        let id = self.next_window_id;
        self.next_window_id += 1;

        let window = Window {
            id,
            title: String::from(title),
            app_type: String::from(app_type),
            x,
            y,
            width,
            height,
            saved_x: x,
            saved_y: y,
            saved_width: width,
            saved_height: height,
            state: WindowState::Normal,
            is_focused: true,
            is_draggable: true,
            is_resizable: true,
            render_content: Box::new(render_content),
        };

        // Unfocus other windows
        for w in self.windows.iter_mut() {
            w.is_focused = false;
        }

        self.windows.push(window);
        self.focused_window_id = Some(id);
        id
    }

    pub fn focus_window(&mut self, id: usize) {
        if let Some(pos) = self.windows.iter().position(|w| w.id == id) {
            let mut window = self.windows.remove(pos);
            window.is_focused = true;
            if window.state == WindowState::Minimized {
                window.state = WindowState::Normal;
            }

            for w in self.windows.iter_mut() {
                w.is_focused = false;
            }

            self.windows.push(window);
            self.focused_window_id = Some(id);
        }
    }

    pub fn close_window(&mut self, id: usize) {
        if let Some(pos) = self.windows.iter().position(|w| w.id == id) {
            self.windows.remove(pos);
            if self.focused_window_id == Some(id) {
                self.focused_window_id = self.windows.last().map(|w| w.id);
                if let Some(top_id) = self.focused_window_id {
                    if let Some(top_w) = self.windows.iter_mut().find(|w| w.id == top_id) {
                        top_w.is_focused = true;
                    }
                }
            }
        }
    }

    pub fn maximize_window(&mut self, id: usize) {
        if let Some(w) = self.windows.iter_mut().find(|w| w.id == id) {
            match w.state {
                WindowState::Maximized => {
                    // Restore to previous bounds
                    w.x = w.saved_x;
                    w.y = w.saved_y;
                    w.width = w.saved_width;
                    w.height = w.saved_height;
                    w.state = WindowState::Normal;
                }
                _ => {
                    // Maximize between Top Menu Bar and Dock Safe-Zone
                    w.saved_x = w.x;
                    w.saved_y = w.y;
                    w.saved_width = w.width;
                    w.saved_height = w.height;

                    let dock_reserve = DOCK_HEIGHT + DOCK_BOTTOM_MARGIN + 4;
                    w.x = 0;
                    w.y = TOP_MENUBAR_HEIGHT;
                    w.width = self.screen_width;
                    w.height = self.screen_height.saturating_sub(TOP_MENUBAR_HEIGHT + dock_reserve);
                    w.state = WindowState::Maximized;
                }
            }
        }
    }

    pub fn minimize_window(&mut self, id: usize) {
        if let Some(w) = self.windows.iter_mut().find(|w| w.id == id) {
            w.state = WindowState::Minimized;
            w.is_focused = false;
            // Focus next topmost window
            self.focused_window_id = self
                .windows
                .iter()
                .rev()
                .find(|win| win.state != WindowState::Minimized)
                .map(|win| win.id);
            if let Some(top_id) = self.focused_window_id {
                if let Some(top_w) = self.windows.iter_mut().find(|w| w.id == top_id) {
                    top_w.is_focused = true;
                }
            }
        }
    }

    pub fn snap_window(&mut self, id: usize, snap_left: bool) {
        if let Some(w) = self.windows.iter_mut().find(|w| w.id == id) {
            w.saved_x = w.x;
            w.saved_y = w.y;
            w.saved_width = w.width;
            w.saved_height = w.height;

            let half_width = self.screen_width / 2;
            let dock_reserve = DOCK_HEIGHT + DOCK_BOTTOM_MARGIN + 4;
            let usable_height = self.screen_height.saturating_sub(TOP_MENUBAR_HEIGHT + dock_reserve);

            if snap_left {
                w.x = 0;
                w.y = TOP_MENUBAR_HEIGHT;
                w.width = half_width;
                w.height = usable_height;
                w.state = WindowState::SnappedLeft;
            } else {
                w.x = half_width;
                w.y = TOP_MENUBAR_HEIGHT;
                w.width = half_width;
                w.height = usable_height;
                w.state = WindowState::SnappedRight;
            }
        }
    }

    /// Process Mouse Input across Top Menu Bar, Windows, and Floating macOS Dock
    pub fn handle_mouse_input(&mut self, mouse: MouseState) {
        let mx = mouse.x as usize;
        let my = mouse.y as usize;

        // Calculate Dock bounds
        let dock_total_items = self.dock_items.len() + self.count_minimized_windows();
        let dock_w = dock_total_items * DOCK_ITEM_WIDTH + 24;
        let dock_x = (self.screen_width.saturating_sub(dock_w)) / 2;
        let dock_y = self.screen_height.saturating_sub(DOCK_HEIGHT + DOCK_BOTTOM_MARGIN);

        // Update Dock Hover State for Magnification
        if my >= dock_y && my <= dock_y + DOCK_HEIGHT && mx >= dock_x && mx <= dock_x + dock_w {
            let rel_x = mx - dock_x;
            self.hovered_dock_index = Some(rel_x / DOCK_ITEM_WIDTH);
        } else {
            self.hovered_dock_index = None;
        }

        if mouse.left_clicked() {
            // 1. Check Global Top Menu Bar
            if my <= TOP_MENUBAR_HEIGHT {
                // Check [ ❖ NEUXON ] Logo Button
                if mx <= 120 {
                    self.apple_menu_open = !self.apple_menu_open;
                    return;
                }
                self.apple_menu_open = false;
                return;
            }

            // 2. Check Apple System Menu Dropdown
            if self.apple_menu_open {
                let menu_w = 200;
                let menu_h = 140;
                if mx <= menu_w && my > TOP_MENUBAR_HEIGHT && my <= TOP_MENUBAR_HEIGHT + menu_h {
                    let item_idx = (my - TOP_MENUBAR_HEIGHT) / (FONT_HEIGHT + 4);
                    self.handle_system_menu_selection(item_idx);
                    self.apple_menu_open = false;
                    return;
                } else {
                    self.apple_menu_open = false;
                }
            }

            // 3. Check Floating macOS Dock clicks
            if my >= dock_y && my <= dock_y + DOCK_HEIGHT && mx >= dock_x && mx <= dock_x + dock_w {
                let rel_x = mx - dock_x;
                let item_idx = rel_x / DOCK_ITEM_WIDTH;

                if item_idx < self.dock_items.len() {
                    let app_type = self.dock_items[item_idx].app_type;
                    self.launch_or_raise_app(app_type);
                } else {
                    // Minimized window restore from drawer
                    let min_idx = item_idx - self.dock_items.len();
                    self.restore_minimized_window(min_idx);
                }
                return;
            }

            // 4. Check Windows & Top-Left macOS Traffic Light Buttons
            for window in self.windows.iter().rev() {
                if window.state == WindowState::Minimized {
                    continue;
                }

                if mx >= window.x && mx < window.x + window.width
                    && my >= window.y && my < window.y + window.height
                {
                    let wid = window.id;
                    self.focus_window(wid);

                    // Check Title Bar Interaction
                    if my >= window.y && my < window.y + FONT_HEIGHT + 6 {
                        // Top-Left macOS Traffic Light Controls:
                        // Close [ ✕ ]: x+6 to x+28
                        // Minimize [ − ]: x+30 to x+52
                        // Zoom [ + ]: x+54 to x+76
                        if mx >= window.x + 6 && mx < window.x + 28 {
                            self.close_window(wid);
                            return;
                        } else if mx >= window.x + 30 && mx < window.x + 52 {
                            self.minimize_window(wid);
                            return;
                        } else if mx >= window.x + 54 && mx < window.x + 76 {
                            self.maximize_window(wid);
                            return;
                        }

                        // Begin Window Drag
                        self.dragging_window_id = Some(wid);
                        self.drag_offset_x = mx.saturating_sub(window.x);
                        self.drag_offset_y = my.saturating_sub(window.y);
                    }
                    return;
                }
            }
        }

        // Handle Window Dragging & Edge Snapping
        if mouse.buttons.left {
            if let Some(drag_id) = self.dragging_window_id {
                let snap_margin = 16;
                let mut snapped = false;

                if mx <= snap_margin {
                    self.snap_window(drag_id, true);
                    snapped = true;
                } else if mx >= self.screen_width.saturating_sub(snap_margin) {
                    self.snap_window(drag_id, false);
                    snapped = true;
                }

                if !snapped {
                    if let Some(w) = self.windows.iter_mut().find(|w| w.id == drag_id) {
                        w.state = WindowState::Normal;
                        let new_x = mx.saturating_sub(self.drag_offset_x);
                        let new_y = my.saturating_sub(self.drag_offset_y);

                        w.x = new_x.min(self.screen_width.saturating_sub(100));
                        w.y = new_y.clamp(
                            TOP_MENUBAR_HEIGHT,
                            self.screen_height.saturating_sub(DOCK_HEIGHT + 60),
                        );
                    }
                }
            }
        } else {
            self.dragging_window_id = None;
        }
    }

    /// Process Keyboard Navigation (Super key, Alt+Tab, Escape)
    pub fn handle_key_input(&mut self, event: KeyEvent) {
        if event.state != KeyState::Pressed {
            return;
        }

        // Super key toggles Top System Menu
        if event.code == KeyCode::Super {
            self.apple_menu_open = !self.apple_menu_open;
            return;
        }

        if event.code == KeyCode::Escape && self.apple_menu_open {
            self.apple_menu_open = false;
            return;
        }

        // Alt + Tab Window Cycle
        if event.modifiers.alt && event.code == KeyCode::Tab {
            self.cycle_window_focus();
        }
    }

    pub fn cycle_window_focus(&mut self) {
        if self.windows.is_empty() {
            return;
        }
        let first_id = self.windows[0].id;
        self.focus_window(first_id);
    }

    fn count_minimized_windows(&self) -> usize {
        self.windows.iter().filter(|w| w.state == WindowState::Minimized).count()
    }

    fn restore_minimized_window(&mut self, min_idx: usize) {
        let min_wins: Vec<usize> = self
            .windows
            .iter()
            .filter(|w| w.state == WindowState::Minimized)
            .map(|w| w.id)
            .collect();

        if let Some(&target_id) = min_wins.get(min_idx) {
            self.focus_window(target_id);
        }
    }

    fn launch_or_raise_app(&mut self, app_type: &str) {
        // If window already exists, un-minimize and focus it
        if let Some(w) = self.windows.iter().find(|w| w.app_type == app_type) {
            let wid = w.id;
            self.focus_window(wid);
            return;
        }

        // Otherwise launch new window
        match app_type {
            "terminal" => crate::apps::terminal::launch(self),
            "browser" => crate::apps::monochrome::launch(self),
            "files" => crate::apps::files::launch(self),
            "taskmatrix" => crate::apps::task_matrix::launch(self),
            "notes" => {
                // Focus VFS sticky note or spawn note editor
                crate::apps::terminal::launch(self);
            }
            "trash" => {
                // Trash drawer inspection
                crate::apps::files::launch(self);
            }
            _ => {}
        }
    }

    fn handle_system_menu_selection(&mut self, item_idx: usize) {
        match item_idx {
            0 => {
                // About Neuxon OS
                crate::apps::terminal::launch(self);
            }
            1 => {
                // System Settings
                crate::apps::task_matrix::launch(self);
            }
            2 => {
                // Force Quit
                crate::apps::task_matrix::launch(self);
            }
            _ => {}
        }
    }

    /// Check if an app has an active process running (PID > 0)
    fn is_app_active(&self, app_type: &str) -> bool {
        self.windows.iter().any(|w| w.app_type == app_type)
    }

    /// Primary Compositor Frame: Renders desktop grid, widgets, windows, macOS Dock, and Top Menu Bar
    pub fn compose(&mut self, display: &mut MonoDisplay, mouse: MouseState) {
        // 1. Clear Desktop with 1-Bit Dithered Dot Matrix Grid
        display.fill_dithered_rect(
            0,
            TOP_MENUBAR_HEIGHT,
            self.screen_width,
            self.screen_height.saturating_sub(TOP_MENUBAR_HEIGHT),
            ShadingPattern::Light,
        );

        // 2. Render Live Desktop Widgets (Within Safe-Zones between Top Bar and Dock)
        self.widgets.render_all(display);

        // 3. Render Windows in Z-Order (Bottom to Top)
        let num_windows = self.windows.len();
        for i in 0..num_windows {
            let (wx, wy, ww, wh, state, focused, title) = {
                let w = &self.windows[i];
                (w.x, w.y, w.width, w.height, w.state, w.is_focused, w.title.clone())
            };

            if state == WindowState::Minimized {
                continue;
            }

            // Window Drop Shadow (1-Bit Bayer Medium Dither)
            display.fill_dithered_rect(
                wx + 6,
                wy + 6,
                ww,
                wh,
                ShadingPattern::Dark,
            );

            // Window Client Area Background (Pure Black)
            display.fill_rect(wx, wy, ww, wh, false);

            // Window Structural Double-Line Borders
            display.draw_double_box(wx, wy, ww, wh, None);

            // Title Bar
            let titlebar_h = FONT_HEIGHT + 4;
            let titlebar_bg = if focused { true } else { false };
            let title_fg = !titlebar_bg;

            display.fill_rect(wx + 2, wy + 2, ww.saturating_sub(4), titlebar_h, titlebar_bg);

            // macOS-Style Top-Left Character Traffic Lights: [ ✕ ][ − ][ + ]
            let close_btn = "[ ✕ ]";
            let min_btn   = "[ − ]";
            let zoom_btn  = "[ + ]";

            display.draw_str(wx + 6,  wy + 3, close_btn, title_fg, Some(titlebar_bg));
            display.draw_str(wx + 34, wy + 3, min_btn,   title_fg, Some(titlebar_bg));
            display.draw_str(wx + 62, wy + 3, zoom_btn,  title_fg, Some(titlebar_bg));

            // Window Title Text (Positioned after traffic lights)
            let title_pos = wx + 92;
            let title_display = format!(" {} ", title);
            display.draw_str(title_pos, wy + 3, &title_display, title_fg, Some(titlebar_bg));

            // Content Area Inset
            let content_x = wx + FONT_WIDTH;
            let content_y = wy + titlebar_h + 4;
            let content_w = ww.saturating_sub(2 * FONT_WIDTH);
            let content_h = wh.saturating_sub(titlebar_h + FONT_HEIGHT);

            // Execute Window Content Callback
            (self.windows[i].render_content)(display, content_x, content_y, content_w, content_h);
        }

        // 4. Render Centered Floating macOS Character Dock (with Hover Magnification & Glow Dots)
        self.render_macos_dock(display, mouse);

        // 5. Render Global Top Menu Bar (Pinned at y = 0)
        self.render_top_menubar(display);

        // 6. Render Apple/Neuxon System Menu Dropdown if Open
        if self.apple_menu_open {
            self.render_system_menu(display);
        }

        // 7. Render 1-Bit Inverted Mouse Cursor on Top of All Layers
        display.render_cursor(mouse.x as usize, mouse.y as usize);

        // 8. Swap Buffers to Hardware Framebuffer
        display.swap_buffers();
    }

    /// Renders the Global macOS-Style Top Menu Bar with Dynamic Contextual Menus
    fn render_top_menubar(&self, display: &mut MonoDisplay) {
        let tw = self.screen_width;

        // Solid Black Top Bar with bottom single-line border
        display.fill_rect(0, 0, tw, TOP_MENUBAR_HEIGHT, true); // White header
        display.draw_line(0, TOP_MENUBAR_HEIGHT as isize, tw as isize, TOP_MENUBAR_HEIGHT as isize, false);

        // Left: Apple / Neuxon Logo
        let logo = " ❖ NEUXON ";
        display.draw_str(4, 3, logo, false, Some(true));
        display.draw_char(84, 3, '│', false, Some(true));

        // Dynamic Contextual App Menus based on Focused Window
        let focused_app = self
            .focused_window_id
            .and_then(|id| self.windows.iter().find(|w| w.id == id))
            .map(|w| w.app_type.as_str())
            .unwrap_or("finder");

        let menu_str = match focused_app {
            "terminal" => " Terminal   Shell   Edit   View   Window   Help",
            "browser"  => " Chromium   File   Edit   View   History   Bookmarks   Help",
            "files"    => " Files   File   Edit   View   Go   Window   Help",
            "taskmatrix"=>" TaskMatrix   Processes   Memory   Inspect   Help",
            _          => " Finder   File   Edit   View   Go   Window   Help",
        };

        display.draw_str(92, 3, menu_str, false, Some(true));

        // Right: System Status Badges
        use core::sync::atomic::Ordering;
        let ticks = crate::arch::x86_64::interrupts::SYSTEM_TICKS.load(Ordering::Relaxed);
        let total_secs = (ticks / 100) + 3600 * 13 + 60 * 30; // 13:30 offset
        let hours = (total_secs / 3600) % 24;
        let mins = (total_secs / 60) % 60;
        let time_badge = format!("{:02}:{:02} UTC", hours, mins);

        let status_right = format!(" [Wi-Fi: ▓▓▓░]  [CPU: 14%]  [{}] ", time_badge);
        let right_x = tw.saturating_sub(status_right.len() * FONT_WIDTH + 8);

        display.draw_str(right_x, 3, &status_right, false, Some(true));
    }

    /// Renders the Apple/Neuxon System Menu Dropdown
    fn render_system_menu(&self, display: &mut MonoDisplay) {
        let sm_x = 4;
        let sm_y = TOP_MENUBAR_HEIGHT + 1;
        let sm_w = 210;
        let sm_h = 130;

        // Drop shadow
        display.fill_dithered_rect(sm_x + 4, sm_y + 4, sm_w, sm_h, ShadingPattern::Dark);
        // Menu body
        display.fill_rect(sm_x, sm_y, sm_w, sm_h, false);
        display.draw_double_box(sm_x, sm_y, sm_w, sm_h, Some("NEUXON"));

        let items = [
            " About Neuxon OS...   ",
            " System Preferences... ",
            " Force Quit Process... ",
            " ──────────────────── ",
            " Restart...           ",
            " Shut Down...         ",
        ];

        let mut py = sm_y + FONT_HEIGHT + 2;
        for it in items.iter() {
            display.draw_str(sm_x + FONT_WIDTH, py, it, true, Some(false));
            py += FONT_HEIGHT + 2;
        }
    }

    /// Renders the Centered Floating macOS Character Dock with Hover Magnification & Active Dots
    fn render_macos_dock(&self, display: &mut MonoDisplay, _mouse: MouseState) {
        let total_pinned = self.dock_items.len();
        let minimized_count = self.count_minimized_windows();
        let total_slots = total_pinned + (if minimized_count > 0 { minimized_count + 1 } else { 0 });

        let dock_w = total_slots * DOCK_ITEM_WIDTH + 24;
        let dock_x = (self.screen_width.saturating_sub(dock_w)) / 2;
        let dock_y = self.screen_height.saturating_sub(DOCK_HEIGHT + DOCK_BOTTOM_MARGIN);

        // 1. Dithered Drop Shadow under Dock
        display.fill_dithered_rect(
            dock_x + 4,
            dock_y + 4,
            dock_w,
            DOCK_HEIGHT,
            ShadingPattern::Dark,
        );

        // 2. Dock Container Background (Pure Black)
        display.fill_rect(dock_x, dock_y, dock_w, DOCK_HEIGHT, false);

        // 3. Rounded Character Border (╭ ─ ╮ │ ╰ ─ ╯)
        display.draw_rounded_box(dock_x, dock_y, dock_w, DOCK_HEIGHT, None);

        // 4. Render Pinned Application Icons
        let mut cur_x = dock_x + 12;

        for (idx, item) in self.dock_items.iter().enumerate() {
            let is_hovered = self.hovered_dock_index == Some(idx);
            let is_active = self.is_app_active(item.app_type);

            // Hover Elevation: If hovered, lift icon by 4px
            let icon_y = if is_hovered { dock_y.saturating_sub(4) } else { dock_y + 4 };

            // Draw Icon Badge
            if is_hovered {
                // Elevated badge with double-line character frame
                display.draw_char(cur_x + 6,  icon_y + 2, '╔', true, Some(false));
                display.draw_char(cur_x + 14, icon_y + 2, '═', true, Some(false));
                display.draw_char(cur_x + 22, icon_y + 2, '╗', true, Some(false));

                display.draw_str(cur_x + 4, icon_y + 10, item.glyph, true, Some(false));

                display.draw_char(cur_x + 6,  icon_y + 18, '╚', true, Some(false));
                display.draw_char(cur_x + 14, icon_y + 18, '═', true, Some(false));
                display.draw_char(cur_x + 22, icon_y + 18, '╝', true, Some(false));

                // Floating Tooltip above icon
                let tooltip = format!("╡ {} ╞", item.label);
                let tip_x = cur_x.saturating_sub(12);
                let tip_y = dock_y.saturating_sub(FONT_HEIGHT + 8);
                display.fill_rect(tip_x, tip_y, tooltip.len() * FONT_WIDTH, FONT_HEIGHT + 2, false);
                display.draw_str(tip_x, tip_y, &tooltip, true, Some(false));
            } else {
                // Normal badge
                display.draw_str(cur_x + 8, icon_y + 6, item.glyph, true, Some(false));
            }

            // Active Process Indicator Dot (•) directly beneath icon
            if is_active {
                display.draw_char(cur_x + 14, dock_y + DOCK_HEIGHT - 12, '•', true, Some(false));
            }

            cur_x += DOCK_ITEM_WIDTH;
        }

        // 5. Minimized Windows Drawer (Separated by Vertical Divider ║)
        if minimized_count > 0 {
            // Divider
            for py in (dock_y + 6)..(dock_y + DOCK_HEIGHT - 6) {
                display.draw_char(cur_x + 4, py, '║', true, Some(false));
            }
            cur_x += 16;

            // Render Minimized Window Badges
            for (m_idx, w) in self.windows.iter().filter(|w| w.state == WindowState::Minimized).enumerate() {
                let dock_slot_idx = total_pinned + m_idx;
                let is_hovered = self.hovered_dock_index == Some(dock_slot_idx);
                let icon_y = if is_hovered { dock_y.saturating_sub(4) } else { dock_y + 4 };

                // Minimized badge [ 🗗 ]
                display.draw_str(cur_x + 4, icon_y + 6, "[🗗]", true, Some(false));

                // Floating tooltip
                if is_hovered {
                    let tooltip = format!("╡ {} ╞", &w.title);
                    let tip_x = cur_x.saturating_sub(20);
                    let tip_y = dock_y.saturating_sub(FONT_HEIGHT + 8);
                    display.fill_rect(tip_x, tip_y, tooltip.len() * FONT_WIDTH, FONT_HEIGHT + 2, false);
                    display.draw_str(tip_x, tip_y, &tooltip, true, Some(false));
                }

                cur_x += DOCK_ITEM_WIDTH;
            }
        }
    }
}

pub static WM: Mutex<Option<WindowManager>> = Mutex::new(None);

pub fn init(screen_width: usize, screen_height: usize) {
    *WM.lock() = Some(WindowManager::new(screen_width, screen_height));
    crate::arch::x86_64::serial_println!(
        "[NeuxonWM] macOS-Style Character Dock & Top Menu Bar initialized ({}x{}).",
        screen_width,
        screen_height
    );
}
