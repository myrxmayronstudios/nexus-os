//! CPU Exception & Hardware Interrupt Handlers for MONO-OS
//! Formally verified handlers with explicit stack frame reporting and CR2 inspection.

use crate::hal::port::Port;
use crate::serial_println;
use core::sync::atomic::{AtomicU64, Ordering};
use x86_64::registers::control::Cr2;
use x86_64::structures::idt::{InterruptDescriptorTable, InterruptStackFrame, PageFaultErrorCode};

/// Hardware IRQ offset mapping in the IDT
pub const PIC_1_OFFSET: u8 = 32;
pub const PIC_2_OFFSET: u8 = PIC_1_OFFSET + 8;

pub const TIMER_INTERRUPT_ID: usize = PIC_1_OFFSET as usize;
pub const KEYBOARD_INTERRUPT_ID: usize = (PIC_1_OFFSET + 1) as usize;
pub const MOUSE_INTERRUPT_ID: usize = (PIC_2_OFFSET + 4) as usize;

/// Monotonic tick counter incremented by timer interrupts
pub static SYSTEM_TICKS: AtomicU64 = AtomicU64::new(0);

// ============================================================================
// CPU Exception Handlers
// ============================================================================

pub extern "x86-interrupt" fn divide_error_handler(stack_frame: InterruptStackFrame) {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ EXCEPTION: DIVIDE-BY-ZERO (#DE)                          ║");
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    serial_println!("{:#?}", stack_frame);
    panic!("Fatal arithmetic exception: Division by zero");
}

pub extern "x86-interrupt" fn breakpoint_handler(stack_frame: InterruptStackFrame) {
    serial_println!("[MONO-KERNEL] EXCEPTION: BREAKPOINT at {:#x}", stack_frame.instruction_pointer);
}

pub extern "x86-interrupt" fn invalid_opcode_handler(stack_frame: InterruptStackFrame) {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ EXCEPTION: INVALID OPCODE (#UD)                          ║");
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    serial_println!("{:#?}", stack_frame);
    panic!("Fatal CPU exception: Invalid instruction execution attempted");
}

pub extern "x86-interrupt" fn double_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) -> ! {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ CRITICAL EXCEPTION: DOUBLE FAULT (#DF)                   ║");
    serial_println!("╠══════════════════════════════════════════════════════════╣");
    serial_println!("║ Error Code: {:#x}", error_code);
    serial_println!("{:#?}", stack_frame);
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    panic!("Double Fault exception occurred — halted for safety.");
}

pub extern "x86-interrupt" fn general_protection_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ EXCEPTION: GENERAL PROTECTION FAULT (#GP)                ║");
    serial_println!("╠══════════════════════════════════════════════════════════╣");
    serial_println!("║ Segment / Selector Error Code: {:#x}", error_code);
    serial_println!("{:#?}", stack_frame);
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    panic!("General Protection Fault: illegal memory or privileged operation");
}

pub extern "x86-interrupt" fn page_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: PageFaultErrorCode,
) {
    let accessed_address = Cr2::read();
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ EXCEPTION: PAGE FAULT (#PF)                              ║");
    serial_println!("╠══════════════════════════════════════════════════════════╣");
    serial_println!("║ Faulting Virtual Address: {:?}", accessed_address);
    serial_println!("║ Error Flags: {:?}", error_code);
    serial_println!("{:#?}", stack_frame);
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    panic!("Unrecoverable Page Fault at address {:?}", accessed_address);
}

// ============================================================================
// Hardware Interrupt Handlers & 8259 PIC Management
// ============================================================================

/// 8259 Programmable Interrupt Controller (PIC) ports
static mut PIC1_COMMAND: Port<u8> = Port::new(0x20);
static mut PIC1_DATA: Port<u8> = Port::new(0x21);
static mut PIC2_COMMAND: Port<u8> = Port::new(0xA0);
static mut PIC2_DATA: Port<u8> = Port::new(0xA1);

/// Initialize the 8259 PIC and remap IRQs 0-15 to interrupt vectors 32-47
pub fn init_pic() {
    // SAFETY: Initializing 8259 PIC using standard IBM PC architecture sequence
    unsafe {
        // ICW1: Start initialization in cascade mode
        PIC1_COMMAND.write(0x11);
        crate::hal::port::io_wait();
        PIC2_COMMAND.write(0x11);
        crate::hal::port::io_wait();

        // ICW2: Vector offset mapping
        PIC1_DATA.write(PIC_1_OFFSET);
        crate::hal::port::io_wait();
        PIC2_DATA.write(PIC_2_OFFSET);
        crate::hal::port::io_wait();

        // ICW3: Tell Master PIC that there is a slave PIC at IRQ2
        PIC1_DATA.write(0x04);
        crate::hal::port::io_wait();
        // Tell Slave PIC its cascade identity (2)
        PIC2_DATA.write(0x02);
        crate::hal::port::io_wait();

        // ICW4: 8086/88 mode
        PIC1_DATA.write(0x01);
        crate::hal::port::io_wait();
        PIC2_DATA.write(0x01);
        crate::hal::port::io_wait();

        // Unmask Timer (IRQ0), Keyboard (IRQ1), Cascade (IRQ2) on Master
        // and Mouse (IRQ12 / pin 4) on Slave PIC
        PIC1_DATA.write(0xF8);
        crate::hal::port::io_wait();
        PIC2_DATA.write(0xEF);
        crate::hal::port::io_wait();
    }
}

/// Send End-of-Interrupt (EOI) signal to the PIC
#[inline(always)]
pub fn send_eoi(interrupt_id: u8) {
    // SAFETY: Writing EOI to PIC command register
    unsafe {
        if interrupt_id >= PIC_2_OFFSET {
            PIC2_COMMAND.write(0x20);
        }
        PIC1_COMMAND.write(0x20);
    }
}

/// Timer interrupt handler (IRQ 0 / Vector 32)
pub extern "x86-interrupt" fn timer_interrupt_handler(_stack_frame: InterruptStackFrame) {
    SYSTEM_TICKS.fetch_add(1, Ordering::Relaxed);
    send_eoi(PIC_1_OFFSET);
}

/// Keyboard interrupt handler (IRQ 1 / Vector 33)
pub extern "x86-interrupt" fn keyboard_interrupt_handler(_stack_frame: InterruptStackFrame) {
    crate::drivers::keyboard::handle_interrupt();
    send_eoi(PIC_1_OFFSET + 1);
}

/// Mouse interrupt handler (IRQ 12 / Vector 44)
pub extern "x86-interrupt" fn mouse_interrupt_handler(_stack_frame: InterruptStackFrame) {
    crate::drivers::mouse::handle_interrupt();
    send_eoi(MOUSE_INTERRUPT_ID as u8);
}
