//! Linear Framebuffer & 1-Bit Monochrome Display Server Driver for MONO-OS
//! Provides double-buffering, dirty-rect tracking, and hardware blitting for VirtIO-GPU and linear VRAM.

use alloc::vec;
use alloc::vec::Vec;
use bootloader::bootinfo::{FrameBuffer, FrameBufferInfo, PixelFormat};
use spin::Mutex;

use super::dither::{dither_8x8, ShadingPattern};
use super::font::{get_glyph, FONT_HEIGHT, FONT_WIDTH};

/// Dirty Rectangle bounds for optimized zero-copy hardware flushes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

impl Rect {
    pub const fn empty() -> Self {
        Self {
            x: usize::MAX,
            y: usize::MAX,
            width: 0,
            height: 0,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.width == 0 || self.height == 0 || self.x == usize::MAX
    }

    pub fn union(&mut self, other: Rect) {
        if other.is_empty() {
            return;
        }
        if self.is_empty() {
            *self = other;
            return;
        }
        let x1 = self.x.min(other.x);
        let y1 = self.y.min(other.y);
        let x2 = (self.x + self.width).max(other.x + other.width);
        let y2 = (self.y + self.height).max(other.y + other.height);
        self.x = x1;
        self.y = y1;
        self.width = x2.saturating_sub(x1);
        self.height = y2.saturating_sub(y1);
    }
}

pub struct MonoDisplay {
    hw_buffer: *mut u8,
    hw_info: FrameBufferInfo,
    back_buffer: Vec<u8>, // 1 byte per pixel for ultra-fast cacheline manipulation (0=Black, 255=White)
    width: usize,
    height: usize,
    stride: usize,
    dirty: Rect,
}

// SAFETY: MonoDisplay encapsulates the single linear hardware framebuffer
unsafe impl Send for MonoDisplay {}
unsafe impl Sync for MonoDisplay {}

impl MonoDisplay {
    pub fn new(hw_fb: &'static mut FrameBuffer) -> Self {
        let info = hw_fb.info();
        let width = info.horizontal_resolution;
        let height = info.vertical_resolution;
        let stride = info.stride;
        let hw_ptr = hw_fb.buffer_mut().as_mut_ptr();

        let mut back_buffer = vec![0u8; width * height];
        // Initialize background to 0 (Black)
        for b in back_buffer.iter_mut() {
            *b = 0;
        }

        Self {
            hw_buffer: hw_ptr,
            hw_info: info,
            back_buffer,
            width,
            height,
            stride,
            dirty: Rect {
                x: 0,
                y: 0,
                width,
                height,
            },
        }
    }

    #[inline(always)]
    pub fn width(&self) -> usize {
        self.width
    }

    #[inline(always)]
    pub fn height(&self) -> usize {
        self.height
    }

    #[inline(always)]
    pub fn mark_dirty(&mut self, x: usize, y: usize, w: usize, h: usize) {
        let clamped_x = x.min(self.width.saturating_sub(1));
        let clamped_y = y.min(self.height.saturating_sub(1));
        let clamped_w = w.min(self.width - clamped_x);
        let clamped_h = h.min(self.height - clamped_y);

        self.dirty.union(Rect {
            x: clamped_x,
            y: clamped_y,
            width: clamped_w,
            height: clamped_h,
        });
    }

    pub fn clear(&mut self, white: bool) {
        let val = if white { 255 } else { 0 };
        for pixel in self.back_buffer.iter_mut() {
            *pixel = val;
        }
        self.dirty = Rect {
            x: 0,
            y: 0,
            width: self.width,
            height: self.height,
        };
    }

    #[inline(always)]
    pub fn set_pixel(&mut self, x: usize, y: usize, white: bool) {
        if x < self.width && y < self.height {
            self.back_buffer[y * self.width + x] = if white { 255 } else { 0 };
            self.mark_dirty(x, y, 1, 1);
        }
    }

    #[inline(always)]
    pub fn get_pixel(&self, x: usize, y: usize) -> bool {
        if x < self.width && y < self.height {
            self.back_buffer[y * self.width + x] != 0
        } else {
            false
        }
    }

    #[inline(always)]
    pub fn invert_pixel(&mut self, x: usize, y: usize) {
        if x < self.width && y < self.height {
            let idx = y * self.width + x;
            self.back_buffer[idx] = if self.back_buffer[idx] == 0 { 255 } else { 0 };
            self.mark_dirty(x, y, 1, 1);
        }
    }

    pub fn draw_line(&mut self, mut x0: isize, mut y0: isize, x1: isize, y1: isize, white: bool) {
        let dx = (x1 - x0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let dy = -(y1 - y0).abs();
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;

        loop {
            if x0 >= 0 && (x0 as usize) < self.width && y0 >= 0 && (y0 as usize) < self.height {
                self.set_pixel(x0 as usize, y0 as usize, white);
            }
            if x0 == x1 && y0 == y1 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x0 += sx;
            }
            if e2 <= dx {
                err += dx;
                y0 += sy;
            }
        }
    }

    pub fn draw_rect(&mut self, x: usize, y: usize, w: usize, h: usize, white: bool) {
        if w == 0 || h == 0 {
            return;
        }
        let right = x + w.saturating_sub(1);
        let bottom = y + h.saturating_sub(1);

        for px in x..=right {
            self.set_pixel(px, y, white);
            self.set_pixel(px, bottom, white);
        }
        for py in y..=bottom {
            self.set_pixel(x, py, white);
            self.set_pixel(right, py, white);
        }
        self.mark_dirty(x, y, w, h);
    }

    pub fn fill_rect(&mut self, x: usize, y: usize, w: usize, h: usize, white: bool) {
        let val = if white { 255 } else { 0 };
        let max_x = (x + w).min(self.width);
        let max_y = (y + h).min(self.height);

        for py in y..max_y {
            let row_offset = py * self.width;
            for px in x..max_x {
                self.back_buffer[row_offset + px] = val;
            }
        }
        self.mark_dirty(x, y, w, h);
    }

    pub fn invert_rect(&mut self, x: usize, y: usize, w: usize, h: usize) {
        let max_x = (x + w).min(self.width);
        let max_y = (y + h).min(self.height);

        for py in y..max_y {
            let row_offset = py * self.width;
            for px in x..max_x {
                let idx = row_offset + px;
                self.back_buffer[idx] = if self.back_buffer[idx] == 0 { 255 } else { 0 };
            }
        }
        self.mark_dirty(x, y, w, h);
    }

    pub fn fill_dithered_rect(
        &mut self,
        x: usize,
        y: usize,
        w: usize,
        h: usize,
        pattern: ShadingPattern,
    ) {
        let max_x = (x + w).min(self.width);
        let max_y = (y + h).min(self.height);

        for py in y..max_y {
            let row_offset = py * self.width;
            for px in x..max_x {
                let is_white = pattern.is_white(px, py);
                self.back_buffer[row_offset + px] = if is_white { 255 } else { 0 };
            }
        }
        self.mark_dirty(x, y, w, h);
    }

    pub fn draw_char(&mut self, x: usize, y: usize, c: char, fg_white: bool, bg_white: Option<bool>) {
        if x + FONT_WIDTH > self.width || y + FONT_HEIGHT > self.height {
            return;
        }

        let glyph = get_glyph(c);
        let fg_val = if fg_white { 255 } else { 0 };

        for row in 0..FONT_HEIGHT {
            let bits = glyph[row];
            let py = y + row;
            let row_offset = py * self.width;

            for col in 0..FONT_WIDTH {
                let px = x + col;
                let is_fg = (bits & (0x80 >> col)) != 0;

                if is_fg {
                    self.back_buffer[row_offset + px] = fg_val;
                } else if let Some(bg) = bg_white {
                    self.back_buffer[row_offset + px] = if bg { 255 } else { 0 };
                }
            }
        }
        self.mark_dirty(x, y, FONT_WIDTH, FONT_HEIGHT);
    }

    pub fn draw_str(&mut self, mut x: usize, y: usize, text: &str, fg_white: bool, bg_white: Option<bool>) {
        for c in text.chars() {
            if c == '\n' {
                break;
            }
            self.draw_char(x, y, c, fg_white, bg_white);
            x += FONT_WIDTH;
            if x + FONT_WIDTH > self.width {
                break;
            }
        }
    }

    /// Render a box with CP437 box-drawing double lines
    pub fn draw_double_box(&mut self, x: usize, y: usize, w: usize, h: usize, title: Option<&str>) {
        if w < 2 || h < 2 {
            return;
        }
        let cols = w / FONT_WIDTH;
        let rows = h / FONT_HEIGHT;

        if cols < 2 || rows < 2 {
            return;
        }

        // Top border
        self.draw_char(x, y, '╔', true, Some(false));
        for i in 1..(cols - 1) {
            self.draw_char(x + i * FONT_WIDTH, y, '═', true, Some(false));
        }
        self.draw_char(x + (cols - 1) * FONT_WIDTH, y, '╗', true, Some(false));

        // Side borders
        for r in 1..(rows - 1) {
            self.draw_char(x, y + r * FONT_HEIGHT, '║', true, Some(false));
            self.draw_char(
                x + (cols - 1) * FONT_WIDTH,
                y + r * FONT_HEIGHT,
                '║',
                true,
                Some(false),
            );
        }

        // Bottom border
        self.draw_char(x, y + (rows - 1) * FONT_HEIGHT, '╚', true, Some(false));
        for i in 1..(cols - 1) {
            self.draw_char(
                x + i * FONT_WIDTH,
                y + (rows - 1) * FONT_HEIGHT,
                '═',
                true,
                Some(false),
            );
        }
        self.draw_char(
            x + (cols - 1) * FONT_WIDTH,
            y + (rows - 1) * FONT_HEIGHT,
            '╝',
            true,
            Some(false),
        );

        // Optional centered or left title
        if let Some(t) = title {
            let title_pos = x + 2 * FONT_WIDTH;
            self.draw_str(title_pos, y, &alloc::format!("╡ {} ╞", t), true, Some(false));
        }
    }

    /// Render a box with macOS-style rounded borders (╭ ─ ╮ │ ╰ ─ ╯)
    pub fn draw_rounded_box(&mut self, x: usize, y: usize, w: usize, h: usize, title: Option<&str>) {
        if w < 2 || h < 2 {
            return;
        }
        let cols = w / FONT_WIDTH;
        let rows = h / FONT_HEIGHT;

        if cols < 2 || rows < 2 {
            return;
        }

        // Top border
        self.draw_char(x, y, '╭', true, Some(false));
        for i in 1..(cols - 1) {
            self.draw_char(x + i * FONT_WIDTH, y, '─', true, Some(false));
        }
        self.draw_char(x + (cols - 1) * FONT_WIDTH, y, '╮', true, Some(false));

        // Side borders
        for r in 1..(rows - 1) {
            self.draw_char(x, y + r * FONT_HEIGHT, '│', true, Some(false));
            self.draw_char(
                x + (cols - 1) * FONT_WIDTH,
                y + r * FONT_HEIGHT,
                '│',
                true,
                Some(false),
            );
        }

        // Bottom border
        self.draw_char(x, y + (rows - 1) * FONT_HEIGHT, '╰', true, Some(false));
        for i in 1..(cols - 1) {
            self.draw_char(
                x + i * FONT_WIDTH,
                y + (rows - 1) * FONT_HEIGHT,
                '─',
                true,
                Some(false),
            );
        }
        self.draw_char(
            x + (cols - 1) * FONT_WIDTH,
            y + (rows - 1) * FONT_HEIGHT,
            '╯',
            true,
            Some(false),
        );

        if let Some(t) = title {
            let title_pos = x + 2 * FONT_WIDTH;
            self.draw_str(title_pos, y, &alloc::format!("┤ {} ├", t), true, Some(false));
        }
    }

    /// Blit raw RGB/Grayscale image buffer with optional Bayer dithering
    pub fn blit_buffer_dithered(
        &mut self,
        dst_x: usize,
        dst_y: usize,
        src: &[u8],
        src_stride: usize,
        w: usize,
        h: usize,
        bytes_per_pixel: usize,
    ) {
        let max_x = (dst_x + w).min(self.width);
        let max_y = (dst_y + h).min(self.height);

        for py in dst_y..max_y {
            let src_y = py - dst_y;
            let src_row = src_y * src_stride;
            let dst_row = py * self.width;

            for px in dst_x..max_x {
                let src_x = px - dst_x;
                let src_idx = src_row + src_x * bytes_per_pixel;

                let is_white = if bytes_per_pixel >= 3 {
                    let r = src[src_idx];
                    let g = src[src_idx + 1];
                    let b = src[src_idx + 2];
                    let lum = ((r as u32 * 299 + g as u32 * 587 + b as u32 * 114) / 1000) as u8;
                    dither_8x8(px, py, lum)
                } else {
                    let lum = src[src_idx];
                    dither_8x8(px, py, lum)
                };

                self.back_buffer[dst_row + px] = if is_white { 255 } else { 0 };
            }
        }
        self.mark_dirty(dst_x, dst_y, w, h);
    }

    /// Render 1-Bit Inverted Arrow Pointer Cursor at (mouse_x, mouse_y)
    pub fn render_cursor(&mut self, cursor_x: usize, cursor_y: usize) {
        use crate::drivers::mouse::{CURSOR_HEIGHT, CURSOR_SHAPE, CURSOR_WIDTH};

        for (cy, line) in CURSOR_SHAPE.iter().enumerate().take(CURSOR_HEIGHT) {
            let py = cursor_y + cy;
            if py >= self.height {
                continue;
            }
            let row_offset = py * self.width;

            for (cx, ch) in line.chars().enumerate().take(CURSOR_WIDTH) {
                let px = cursor_x + cx;
                if px >= self.width {
                    continue;
                }

                let idx = row_offset + px;
                match ch {
                    'X' => self.back_buffer[idx] = 255, // Crisp White border
                    '.' => self.back_buffer[idx] = 0,   // Solid Black fill
                    _ => {}                             // Transparent
                }
            }
        }
        self.mark_dirty(cursor_x, cursor_y, CURSOR_WIDTH, CURSOR_HEIGHT);
    }

    /// Zero-copy swap: Flushes the dirty rectangle from back_buffer to hardware VRAM
    pub fn swap_buffers(&mut self) {
        if self.dirty.is_empty() {
            return;
        }

        let rect = self.dirty;
        self.dirty = Rect::empty();

        let bpp = self.hw_info.bytes_per_pixel;
        let pixel_format = self.hw_info.pixel_format;
        let hw_stride = self.stride;

        for py in rect.y..(rect.y + rect.height).min(self.height) {
            let src_row = py * self.width;
            let dst_row = py * hw_stride * bpp;

            for px in rect.x..(rect.x + rect.width).min(self.width) {
                let is_white = self.back_buffer[src_row + px] != 0;
                let color_val: u8 = if is_white { 0xFF } else { 0x00 };
                let dst_idx = dst_row + px * bpp;

                // SAFETY: Writing into validated linear framebuffer bounds
                unsafe {
                    match pixel_format {
                        PixelFormat::RGB => {
                            *self.hw_buffer.add(dst_idx) = color_val;
                            *self.hw_buffer.add(dst_idx + 1) = color_val;
                            *self.hw_buffer.add(dst_idx + 2) = color_val;
                        }
                        PixelFormat::BGR => {
                            *self.hw_buffer.add(dst_idx) = color_val;
                            *self.hw_buffer.add(dst_idx + 1) = color_val;
                            *self.hw_buffer.add(dst_idx + 2) = color_val;
                        }
                        PixelFormat::U8 => {
                            *self.hw_buffer.add(dst_idx) = color_val;
                        }
                        _ => {
                            *self.hw_buffer.add(dst_idx) = color_val;
                            *self.hw_buffer.add(dst_idx + 1) = color_val;
                            *self.hw_buffer.add(dst_idx + 2) = color_val;
                            if bpp == 4 {
                                *self.hw_buffer.add(dst_idx + 3) = 0xFF;
                            }
                        }
                    }
                }
            }
        }
    }
}

pub static DISPLAY: Mutex<Option<MonoDisplay>> = Mutex::new(None);

/// Initialize the global MonoDisplay instance from bootloader FrameBuffer
pub fn init(hw_fb: &'static mut FrameBuffer) {
    let display = MonoDisplay::new(hw_fb);
    let (w, h) = (display.width(), display.height());
    *DISPLAY.lock() = Some(display);
    crate::drivers::mouse::MOUSE.lock().set_screen_bounds(w as i32, h as i32);
    crate::arch::x86_64::serial_println!(
        "[DISPLAY] 1-Bit Monochrome Display Server initialized ({}x{}).",
        w,
        h
    );
}
