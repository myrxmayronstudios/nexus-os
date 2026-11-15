//! x86_64 Architecture Implementation
//! GDT, IDT, Interrupt Handlers, and Serial UART driver.

pub mod gdt;
pub mod idt;
pub mod interrupts;
pub mod serial;

/// Halt the CPU until the next external interrupt arrives
#[inline(always)]
pub fn hlt() {
    x86_64::instructions::hlt();
}

/// Enable hardware interrupts
#[inline(always)]
pub fn enable_interrupts() {
    x86_64::instructions::interrupts::enable();
}

/// Disable hardware interrupts
#[inline(always)]
pub fn disable_interrupts() {
    x86_64::instructions::interrupts::disable();
}
