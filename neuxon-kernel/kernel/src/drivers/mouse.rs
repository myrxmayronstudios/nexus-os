//! PS/2 Mouse Driver for MONO-OS
//! 3-byte packet decoder, cursor coordinate tracking, and inverted pixel cursor rendering.

use crate::arch::x86_64::serial_println;
use crate::hal::port::{io_wait, Port};
use spin::Mutex;

const DATA_PORT: u16 = 0x60;
const STATUS_PORT: u16 = 0x64;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MouseButtons {
    pub left: bool,
    pub right: bool,
    pub middle: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MouseState {
    pub x: i32,
    pub y: i32,
    pub dx: i32,
    pub dy: i32,
    pub buttons: MouseButtons,
    pub prev_buttons: MouseButtons,
}

impl MouseState {
    pub const fn new() -> Self {
        Self {
            x: 512,
            y: 384,
            dx: 0,
            dy: 0,
            buttons: MouseButtons {
                left: false,
                right: false,
                middle: false,
            },
            prev_buttons: MouseButtons {
                left: false,
                right: false,
                middle: false,
            },
        }
    }

    pub fn left_clicked(&self) -> bool {
        self.buttons.left && !self.prev_buttons.left
    }

    pub fn left_released(&self) -> bool {
        !self.buttons.left && self.prev_buttons.left
    }

    pub fn right_clicked(&self) -> bool {
        self.buttons.right && !self.prev_buttons.right
    }
}

pub struct MouseDriver {
    pub state: MouseState,
    packet: [u8; 3],
    cycle: u8,
    screen_width: i32,
    screen_height: i32,
}

impl MouseDriver {
    pub const fn new() -> Self {
        Self {
            state: MouseState::new(),
            packet: [0; 3],
            cycle: 0,
            screen_width: 1024,
            screen_height: 768,
        }
    }

    pub fn set_screen_bounds(&mut self, width: i32, height: i32) {
        self.screen_width = width;
        self.screen_height = height;
        self.state.x = width / 2;
        self.state.y = height / 2;
    }

    pub fn process_byte(&mut self, byte: u8) -> bool {
        match self.cycle {
            0 => {
                // Bit 3 of byte 0 must be 1 in standard PS/2 mouse packets
                if (byte & 0x08) != 0 {
                    self.packet[0] = byte;
                    self.cycle = 1;
                }
            }
            1 => {
                self.packet[1] = byte;
                self.cycle = 2;
            }
            2 => {
                self.packet[2] = byte;
                self.cycle = 0;
                self.decode_packet();
                return true;
            }
            _ => self.cycle = 0,
        }
        false
    }

    fn decode_packet(&mut self) {
        let flags = self.packet[0];
        let mut raw_dx = self.packet[1] as i32;
        let mut raw_dy = self.packet[2] as i32;

        // Sign extension for 9-bit relative movement
        if (flags & 0x10) != 0 {
            raw_dx |= !0xFF;
        }
        if (flags & 0x20) != 0 {
            raw_dy |= !0xFF;
        }

        // PS/2 Y delta is inverted (positive is upwards, but screen Y is downwards)
        let dy = -raw_dy;
        let dx = raw_dx;

        self.state.dx = dx;
        self.state.dy = dy;

        self.state.prev_buttons = self.state.buttons;
        self.state.buttons.left = (flags & 0x01) != 0;
        self.state.buttons.right = (flags & 0x02) != 0;
        self.state.buttons.middle = (flags & 0x04) != 0;

        // Apply sensitivity and clamp coordinates to screen bounds
        self.state.x += dx;
        self.state.y += dy;

        if self.state.x < 0 {
            self.state.x = 0;
        }
        if self.state.x >= self.screen_width {
            self.state.x = self.screen_width - 1;
        }
        if self.state.y < 0 {
            self.state.y = 0;
        }
        if self.state.y >= self.screen_height {
            self.state.y = self.screen_height - 1;
        }
    }
}

pub static MOUSE: Mutex<MouseDriver> = Mutex::new(MouseDriver::new());

fn mouse_wait(is_signal: u8) {
    let status_port = Port::<u8>::new(STATUS_PORT);
    let mut timeout = 100_000;
    while timeout > 0 {
        let status = status_port.read();
        if is_signal == 0 {
            if (status & 0x02) == 0 {
                return;
            }
        } else {
            if (status & 0x01) == 1 {
                return;
            }
        }
        timeout -= 1;
    }
}

fn mouse_write(write: u8) {
    mouse_wait(0);
    Port::<u8>::new(STATUS_PORT).write(0xD4);
    mouse_wait(0);
    Port::<u8>::new(DATA_PORT).write(write);
}

fn mouse_read() -> u8 {
    mouse_wait(1);
    Port::<u8>::new(DATA_PORT).read()
}

/// Initialize PS/2 Mouse hardware
pub fn init() {
    let mut status_port = Port::<u8>::new(STATUS_PORT);
    let mut data_port = Port::<u8>::new(DATA_PORT);

    // Enable auxiliary mouse device
    mouse_wait(0);
    status_port.write(0xA8);

    // Read Comptroller Command Byte
    mouse_wait(0);
    status_port.write(0x20);
    let status = mouse_read() | 0x02; // Enable IRQ 12

    // Write back Comptroller Command Byte
    mouse_wait(0);
    status_port.write(0x60);
    mouse_wait(0);
    data_port.write(status);

    // Set Default Settings
    mouse_write(0xF6);
    let _ = mouse_read(); // ACK (0xFA)

    // Enable Data Reporting (Streaming Mode)
    mouse_write(0xF4);
    let _ = mouse_read(); // ACK (0xFA)

    serial_println!("[MOUSE] PS/2 Mouse streaming enabled (IRQ 12).");
}

/// Handle Mouse Interrupt (IRQ 12)
pub fn handle_interrupt() {
    let data_port = Port::<u8>::new(DATA_PORT);
    let byte = data_port.read();
    MOUSE.lock().process_byte(byte);
}

/// Snapshot current mouse state
pub fn get_mouse_state() -> MouseState {
    MOUSE.lock().state
}

/// 1-Bit Inverted Arrow Pointer Cursor (16x16 bitmap)
/// 1: Solid White outline/fill, 2: Inverted Black border, 0: Transparent
pub const CURSOR_WIDTH: usize = 12;
pub const CURSOR_HEIGHT: usize = 19;

pub const CURSOR_SHAPE: [&str; 19] = [
    "X...........",
    "XX..........",
    "X.X.........",
    "X..X........",
    "X...X.......",
    "X....X......",
    "X.....X.....",
    "X......X....",
    "X.......X...",
    "X........X..",
    "X.....XXXXXX",
    "X..X..X.....",
    "X.X X..X....",
    "XX   X..X...",
    "X     X..X..",
    "       X..X.",
    "        XX..",
    "         X..",
    "............",
];
