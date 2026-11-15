//! Interrupt Descriptor Table (IDT) Configuration
//! Registers exception handlers and hardware interrupt gates.

use super::gdt;
use super::interrupts::*;
use lazy_static::lazy_static;
use x86_64::structures::idt::InterruptDescriptorTable;

lazy_static! {
    static ref IDT: InterruptDescriptorTable = {
        let mut idt = InterruptDescriptorTable::new();

        // Register standard CPU exceptions
        idt.divide_error.set_handler_fn(divide_error_handler);
        idt.breakpoint.set_handler_fn(breakpoint_handler);
        idt.invalid_opcode.set_handler_fn(invalid_opcode_handler);
        idt.general_protection_fault.set_handler_fn(general_protection_fault_handler);
        idt.page_fault.set_handler_fn(page_fault_handler);

        // Register Double Fault with dedicated Interrupt Stack Table (IST)
        // SAFETY: The stack index is valid and configured in the TSS
        unsafe {
            idt.double_fault
                .set_handler_fn(double_fault_handler)
                .set_stack_index(gdt::DOUBLE_FAULT_IST_INDEX);
        }

        // Register hardware IRQs
        idt[TIMER_INTERRUPT_ID].set_handler_fn(timer_interrupt_handler);
        idt[KEYBOARD_INTERRUPT_ID].set_handler_fn(keyboard_interrupt_handler);
        idt[MOUSE_INTERRUPT_ID].set_handler_fn(mouse_interrupt_handler);

        idt
    };
}

/// Load the Interrupt Descriptor Table into the CPU
pub fn init() {
    IDT.load();
    init_pic();
}
