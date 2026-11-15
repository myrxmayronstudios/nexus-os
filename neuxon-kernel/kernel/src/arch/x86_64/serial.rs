//! 16550 UART Serial Driver for MONO-OS
//! Provides high-speed early boot diagnostics over COM1 (0x3F8).

use crate::hal::port::Port;
use core::fmt;
use spin::Mutex;

const COM1_BASE: u16 = 0x3F8;

/// 16550 UART Controller driver
pub struct SerialPort {
    data: Port<u8>,
    interrupt_enable: Port<u8>,
    fifo_control: Port<u8>,
    line_control: Port<u8>,
    modem_control: Port<u8>,
    line_status: Port<u8>,
}

impl SerialPort {
    /// Create uninitialized serial port targeting COM1 (0x3F8)
    pub const fn new(base: u16) -> Self {
        Self {
            data: Port::new(base),
            interrupt_enable: Port::new(base + 1),
            fifo_control: Port::new(base + 2),
            line_control: Port::new(base + 3),
            modem_control: Port::new(base + 4),
            line_status: Port::new(base + 5),
        }
    }

    /// Initialize UART controller to 115200 baud, 8N1, FIFO enabled
    pub fn init(&mut self) {
        // SAFETY: The initialization sequence follows standard 16550 UART hardware specifications
        unsafe {
            // Disable all interrupts
            self.interrupt_enable.write(0x00);
            // Enable DLAB (set baud rate divisor)
            self.line_control.write(0x80);
            // Set divisor to 1 (low byte: 0x01, high byte: 0x00) => 115200 baud
            self.data.write(0x01);
            self.interrupt_enable.write(0x00);
            // 8 bits, no parity, one stop bit (8N1), clear DLAB
            self.line_control.write(0x03);
            // Enable FIFO, clear TX/RX queues, 14-byte threshold
            self.fifo_control.write(0xC7);
            // IRQs enabled, RTS/DSR set
            self.modem_control.write(0x0B);
        }
    }

    /// Check if the transmitter FIFO/holding register is empty
    fn is_transmit_empty(&self) -> bool {
        // SAFETY: Reading Line Status Register is side-effect free
        unsafe { (self.line_status.read() & 0x20) != 0 }
    }

    /// Send a single byte over the serial line
    pub fn send(&mut self, byte: u8) {
        // Spin until the transmitter buffer is ready to accept a new byte
        while !self.is_transmit_empty() {
            core::hint::spin_loop();
        }
        // SAFETY: Transmitter is confirmed ready, writing to data register transmits byte
        unsafe {
            self.data.write(byte);
        }
    }

    /// Write a string slice to serial output
    pub fn write_str(&mut self, s: &str) {
        for byte in s.bytes() {
            if byte == b'\n' {
                // Ensure carriage return precedes newline for standard terminal viewing
                self.send(b'\r');
            }
            self.send(byte);
        }
    }
}

impl fmt::Write for SerialPort {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.write_str(s);
        Ok(())
    }
}

/// Global COM1 serial port protected by a spinlock
pub static SERIAL1: Mutex<SerialPort> = Mutex::new(SerialPort::new(COM1_BASE));

/// Initialize COM1 serial port
pub fn init() {
    SERIAL1.lock().init();
}

#[doc(hidden)]
pub fn _print(args: fmt::Arguments) {
    use core::fmt::Write;
    use x86_64::instructions::interrupts;

    // Disable interrupts while holding the serial lock to prevent deadlocks with interrupt handlers
    interrupts::without_interrupts(|| {
        SERIAL1
            .lock()
            .write_fmt(args)
            .expect("Failed to write to UART serial port");
    });
}

/// Prints to the serial port
#[macro_export]
macro_rules! serial_print {
    ($($arg:tt)*) => {
        $crate::arch::x86_64::serial::_print(format_args!($($arg)*))
    };
}

/// Prints to the serial port with a newline
#[macro_export]
macro_rules! serial_println {
    () => ($crate::serial_print!("\n"));
    ($($arg:tt)*) => ($crate::serial_print!("{}\n", format_args!($($arg)*)));
}
