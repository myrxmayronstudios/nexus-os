//! PS/2 Keyboard Driver for MONO-OS
//! Decodes Scancode Set 1, tracks modifier state, and buffers KeyEvents for MonoWM.

use crate::arch::x86_64::serial_println;
use crate::hal::port::Port;
use spin::Mutex;

const DATA_PORT: u16 = 0x60;
const STATUS_PORT: u16 = 0x64;

/// Key press/release state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Pressed,
    Released,
}

/// Key Codes recognized by MONO-OS
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyCode {
    Unknown,
    Char(char),
    Enter,
    Backspace,
    Tab,
    Space,
    Escape,
    LeftShift,
    RightShift,
    LeftCtrl,
    RightCtrl,
    LeftAlt,
    RightAlt,
    Super, // Windows / Meta Key
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    Home,
    End,
    PageUp,
    PageDown,
    Delete,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
}

/// Modifier key states
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct KeyModifiers {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub super_key: bool,
    pub caps_lock: bool,
}

/// Discrete keyboard event
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyEvent {
    pub code: KeyCode,
    pub state: KeyState,
    pub char: Option<char>,
    pub modifiers: KeyModifiers,
}

const KEY_BUFFER_CAPACITY: usize = 128;

pub struct KeyboardBuffer {
    buffer: [Option<KeyEvent>; KEY_BUFFER_CAPACITY],
    head: usize,
    tail: usize,
    modifiers: KeyModifiers,
    extended: bool,
}

impl KeyboardBuffer {
    pub const fn new() -> Self {
        Self {
            buffer: [None; KEY_BUFFER_CAPACITY],
            head: 0,
            tail: 0,
            modifiers: KeyModifiers {
                shift: false,
                ctrl: false,
                alt: false,
                super_key: false,
                caps_lock: false,
            },
            extended: false,
        }
    }

    pub fn push(&mut self, event: KeyEvent) {
        let next_head = (self.head + 1) % KEY_BUFFER_CAPACITY;
        if next_head != self.tail {
            self.buffer[self.head] = Some(event);
            self.head = next_head;
        }
    }

    pub fn pop(&mut self) -> Option<KeyEvent> {
        if self.head == self.tail {
            None
        } else {
            let event = self.buffer[self.tail].take();
            self.tail = (self.tail + 1) % KEY_BUFFER_CAPACITY;
            event
        }
    }
}

pub static KEYBOARD: Mutex<KeyboardBuffer> = Mutex::new(KeyboardBuffer::new());

/// Initialize PS/2 Keyboard
pub fn init() {
    let status_port = Port::<u8>::new(STATUS_PORT);
    // Flush any pending scancodes
    while status_port.read() & 0x01 != 0 {
        let data_port = Port::<u8>::new(DATA_PORT);
        let _ = data_port.read();
    }
    serial_println!("[KEYBOARD] PS/2 Keyboard initialized.");
}

/// Handle Keyboard IRQ (called from IRQ 1)
pub fn handle_interrupt() {
    let data_port = Port::<u8>::new(DATA_PORT);
    let scancode = data_port.read();
    let mut kbd = KEYBOARD.lock();

    // Check for extended scancode prefix (0xE0)
    if scancode == 0xE0 {
        kbd.extended = true;
        return;
    }

    let is_extended = kbd.extended;
    kbd.extended = false;

    let released = (scancode & 0x80) != 0;
    let code = scancode & 0x7F;
    let state = if released { KeyState::Released } else { KeyState::Pressed };

    let key_code = if is_extended {
        decode_extended(code)
    } else {
        decode_standard(code)
    };

    // Update modifier states
    match key_code {
        KeyCode::LeftShift | KeyCode::RightShift => {
            kbd.modifiers.shift = !released;
        }
        KeyCode::LeftCtrl | KeyCode::RightCtrl => {
            kbd.modifiers.ctrl = !released;
        }
        KeyCode::LeftAlt | KeyCode::RightAlt => {
            kbd.modifiers.alt = !released;
        }
        KeyCode::Super => {
            kbd.modifiers.super_key = !released;
        }
        _ => {}
    }

    let char_val = if state == KeyState::Pressed {
        to_char(key_code, &kbd.modifiers)
    } else {
        None
    };

    let event = KeyEvent {
        code: key_code,
        state,
        char: char_val,
        modifiers: kbd.modifiers,
    };

    kbd.push(event);
}

/// Pop next key event for GUI compositor
pub fn pop_key_event() -> Option<KeyEvent> {
    KEYBOARD.lock().pop()
}

fn decode_standard(code: u8) -> KeyCode {
    match code {
        0x01 => KeyCode::Escape,
        0x02 => KeyCode::Char('1'),
        0x03 => KeyCode::Char('2'),
        0x04 => KeyCode::Char('3'),
        0x05 => KeyCode::Char('4'),
        0x06 => KeyCode::Char('5'),
        0x07 => KeyCode::Char('6'),
        0x08 => KeyCode::Char('7'),
        0x09 => KeyCode::Char('8'),
        0x0A => KeyCode::Char('9'),
        0x0B => KeyCode::Char('0'),
        0x0C => KeyCode::Char('-'),
        0x0D => KeyCode::Char('='),
        0x0E => KeyCode::Backspace,
        0x0F => KeyCode::Tab,
        0x10 => KeyCode::Char('q'),
        0x11 => KeyCode::Char('w'),
        0x12 => KeyCode::Char('e'),
        0x13 => KeyCode::Char('r'),
        0x14 => KeyCode::Char('t'),
        0x15 => KeyCode::Char('y'),
        0x16 => KeyCode::Char('u'),
        0x17 => KeyCode::Char('i'),
        0x18 => KeyCode::Char('o'),
        0x19 => KeyCode::Char('p'),
        0x1A => KeyCode::Char('['),
        0x1B => KeyCode::Char(']'),
        0x1C => KeyCode::Enter,
        0x1D => KeyCode::LeftCtrl,
        0x1E => KeyCode::Char('a'),
        0x1F => KeyCode::Char('s'),
        0x20 => KeyCode::Char('d'),
        0x21 => KeyCode::Char('f'),
        0x22 => KeyCode::Char('g'),
        0x23 => KeyCode::Char('h'),
        0x24 => KeyCode::Char('j'),
        0x25 => KeyCode::Char('k'),
        0x26 => KeyCode::Char('l'),
        0x27 => KeyCode::Char(';'),
        0x28 => KeyCode::Char('\''),
        0x29 => KeyCode::Char('`'),
        0x2A => KeyCode::LeftShift,
        0x2B => KeyCode::Char('\\'),
        0x2C => KeyCode::Char('z'),
        0x2D => KeyCode::Char('x'),
        0x2E => KeyCode::Char('c'),
        0x2F => KeyCode::Char('v'),
        0x30 => KeyCode::Char('b'),
        0x31 => KeyCode::Char('n'),
        0x32 => KeyCode::Char('m'),
        0x33 => KeyCode::Char(','),
        0x34 => KeyCode::Char('.'),
        0x35 => KeyCode::Char('/'),
        0x36 => KeyCode::RightShift,
        0x38 => KeyCode::LeftAlt,
        0x39 => KeyCode::Space,
        0x3B => KeyCode::F1,
        0x3C => KeyCode::F2,
        0x3D => KeyCode::F3,
        0x3E => KeyCode::F4,
        0x3F => KeyCode::F5,
        0x40 => KeyCode::F6,
        0x41 => KeyCode::F7,
        0x42 => KeyCode::F8,
        0x43 => KeyCode::F9,
        0x44 => KeyCode::F10,
        0x57 => KeyCode::F11,
        0x58 => KeyCode::F12,
        _ => KeyCode::Unknown,
    }
}

fn decode_extended(code: u8) -> KeyCode {
    match code {
        0x1D => KeyCode::RightCtrl,
        0x38 => KeyCode::RightAlt,
        0x48 => KeyCode::ArrowUp,
        0x4B => KeyCode::ArrowLeft,
        0x4D => KeyCode::ArrowRight,
        0x50 => KeyCode::ArrowDown,
        0x47 => KeyCode::Home,
        0x4F => KeyCode::End,
        0x49 => KeyCode::PageUp,
        0x51 => KeyCode::PageDown,
        0x53 => KeyCode::Delete,
        0x5B => KeyCode::Super, // Left Windows Key
        _ => KeyCode::Unknown,
    }
}

fn to_char(key: KeyCode, mods: &KeyModifiers) -> Option<char> {
    match key {
        KeyCode::Char(c) => {
            if mods.shift {
                let shifted = match c {
                    'a'..='z' => (c as u8 - 32) as char,
                    '1' => '!',
                    '2' => '@',
                    '3' => '#',
                    '4' => '$',
                    '5' => '%',
                    '6' => '^',
                    '7' => '&',
                    '8' => '*',
                    '9' => '(',
                    '0' => ')',
                    '-' => '_',
                    '=' => '+',
                    '[' => '{',
                    ']' => '}',
                    ';' => ':',
                    '\'' => '"',
                    '`' => '~',
                    '\\' => '|',
                    ',' => '<',
                    '.' => '>',
                    '/' => '?',
                    _ => c,
                };
                Some(shifted)
            } else {
                Some(c)
            }
        }
        KeyCode::Space => Some(' '),
        KeyCode::Tab => Some('\t'),
        KeyCode::Enter => Some('\n'),
        _ => None,
    }
}
