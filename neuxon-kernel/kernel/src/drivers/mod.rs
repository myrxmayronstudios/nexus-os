//! MONO-OS Hardware Input Drivers
//! PS/2 Keyboard and Mouse support for x86_64 architecture.

pub mod keyboard;
pub mod mouse;

/// Initialize all hardware input drivers
pub fn init() {
    keyboard::init();
    mouse::init();
}
