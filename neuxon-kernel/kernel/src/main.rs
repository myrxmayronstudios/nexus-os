//! Neuxon OS: High-Performance Rust Exokernel & macOS-Style 1-Bit Monochrome Operating System
//! Designed for zero-latency context switches, lock-free syscall rings, and deterministic GUI responsiveness.

#![no_std]
#![no_main]
#![forbid(unsafe_op_in_unsafe_fn)]
#![feature(abi_x86_interrupt)]
#![feature(alloc_error_handler)]

extern crate alloc;

pub mod abi;
pub mod apps;
pub mod arch;
pub mod drivers;
pub mod gui;
pub mod hal;
pub mod ipc;
pub mod mm;
pub mod sched;
pub mod vfs;

use alloc::boxed::Box;
use alloc::vec::Vec;
use bootloader::bootinfo::{BootInfo, Optional};
use bootloader::entry_point;
use core::panic::PanicInfo;
use core::sync::atomic::Ordering;

// Register bootloader entry point
entry_point!(kernel_main);

/// Primary Kernel Entry Point
fn kernel_main(boot_info: &'static mut BootInfo) -> ! {
    // ------------------------------------------------------------------------
    // 1. Initialize Early Serial Diagnostics (COM1 0x3F8 @ 115200 baud)
    // ------------------------------------------------------------------------
    arch::x86_64::serial::init();

    serial_println!("╔══════════════════════════════════════════════════════════════════╗");
    serial_println!("║      ███╗   ██╗███████╗██╗   ██╗██╗  ██╗ ██████╗ ███╗   ██╗      ║");
    serial_println!("║      ████╗  ██║██╔════╝██║   ██║╚██╗██╔╝██╔═══██╗████╗  ██║      ║");
    serial_println!("║      ██╔██╗ ██║█████╗  ██║   ██║ ╚███╔╝ ██║   ██║██╔██╗ ██║      ║");
    serial_println!("║      ██║╚██╗██║██╔══╝  ██║   ██║ ██╔██╗ ██║   ██║██║╚██╗██║      ║");
    serial_println!("║      ██║ ╚████║███████╗╚██████╔╝██╔╝ ██╗╚██████╔╝██║ ╚████║      ║");
    serial_println!("║      ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝      ║");
    serial_println!("║   NEUXON OS 2.0: ZERO-LATENCY EXOKERNEL & 1-BIT macOS-STYLE UI   ║");
    serial_println!("╚══════════════════════════════════════════════════════════════════╝");
    serial_println!("[NEUXON-KERNEL] Bootloader handoff validated. Long mode active (x86_64).");

    // ------------------------------------------------------------------------
    // 2. Global Descriptor Table & Task State Segment (GDT/TSS)
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing GDT, TSS, and Double-Fault IST stack...");
    arch::x86_64::gdt::init();
    serial_println!("[NEUXON-KERNEL] ✓ GDT loaded with Ring 0/Ring 3 isolation.");

    // ------------------------------------------------------------------------
    // 3. Interrupt Descriptor Table (IDT) & 8259 PIC Remap
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Configuring Interrupt Descriptor Table (256 vectors)...");
    arch::x86_64::idt::init();
    serial_println!("[NEUXON-KERNEL] ✓ IDT active with hardware exception gates & IRQ remap.");

    // ------------------------------------------------------------------------
    // 4. Memory Management Subsystem (Frames + 4-Level Paging + Slab Allocator)
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing physical frames, PML4 mapper, and Slab allocator...");
    mm::init(boot_info);

    let total_frames = mm::frame::TOTAL_USABLE_FRAMES.load(Ordering::SeqCst);
    let total_ram_mb = (total_frames * 4096) / (1024 * 1024);
    serial_println!(
        "[NEUXON-KERNEL] ✓ Memory Subsystem online. Total Usable RAM: {} MB ({} frames).",
        total_ram_mb,
        total_frames
    );

    // Test heap allocation via Box and Vec
    {
        let heap_test_box = Box::new(0xDEAD_BEEF_CAFE_BABEu64);
        let mut heap_test_vec = Vec::new();
        for i in 0..16 {
            heap_test_vec.push(i * 2);
        }
        serial_println!(
            "[NEUXON-KERNEL] ✓ Slab Allocator sanity test passed: Box val={:#X}, Vec len={}.",
            *heap_test_box,
            heap_test_vec.len()
        );
    }

    // ------------------------------------------------------------------------
    // 5. In-Memory Virtual File System (VFS)
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing Virtual File System (/sys, /dev, /home)...");
    vfs::init();

    // ------------------------------------------------------------------------
    // 6. Lock-Free Asynchronous Syscall Ring (MonoRing)
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing Lock-Free Asynchronous Syscall Ring...");
    ipc::ring_buffer::init();

    // Verify ring submission and completion dispatch throughput
    {
        let ring = unsafe { ipc::ring_buffer::get_global_ring() };
        let test_sqe = ipc::ring_buffer::SubmissionQueueEntry {
            opcode: ipc::ring_buffer::OP_NOP,
            flags: 0,
            ioprio: 0,
            fd: 0,
            addr: 0,
            len: 0,
            offset: 0,
            user_data: 0x1337,
            _reserved: [0; 24],
        };
        ring.sq.submit(test_sqe).expect("Failed to submit test SQE");
        let processed = ring.dispatch_pending();
        let cqe = ring.cq.pop().expect("Failed to pop test CQE");
        assert_eq!(cqe.user_data, 0x1337);
        assert_eq!(cqe.res, 0);
        serial_println!(
            "[NEUXON-KERNEL] ✓ Lock-Free Syscall Ring operational (processed {} ops, zero traps).",
            processed
        );
    }

    // ------------------------------------------------------------------------
    // 7. O(1) Cache-Aware Task Scheduler
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing O(1) Work-Stealing Task Scheduler...");
    sched::init();

    // Spawn Idle task
    let idle_task = sched::work_stealing::Task::new(
        sched::work_stealing::TaskId::new(),
        "idle",
        sched::work_stealing::TaskPriority::Idle,
        0,
        idle_worker,
    );
    sched::work_stealing::SCHEDULER
        .lock()
        .spawn(idle_task)
        .expect("Failed to register idle task");

    serial_println!(
        "[NEUXON-KERNEL] ✓ Scheduler ready. Active tasks: {}.",
        sched::work_stealing::ACTIVE_TASKS_COUNT.load(Ordering::Relaxed)
    );

    // ------------------------------------------------------------------------
    // 8. Hardware Input Drivers (PS/2 Keyboard & Mouse)
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing PS/2 Keyboard and Mouse drivers...");
    drivers::init();

    // ------------------------------------------------------------------------
    // 9. NeuxonWM 1-Bit Monochrome Display Server & macOS-Style GUI
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Initializing NeuxonWM macOS-Style Character Dock & Top Bar...");
    if let Optional::Some(ref mut fb) = boot_info.framebuffer {
        let static_fb: &'static mut bootloader::bootinfo::FrameBuffer =
            unsafe { &mut *(fb as *mut _) };
        gui::init(static_fb);

        // Spawn Default Desktop Windows
        if let Some(ref mut wm) = *gui::wm::WM.lock() {
            // Launch NeuxonTerm Shell
            apps::terminal::launch(wm);
            // Launch Neuxon Chromium Host
            apps::monochrome::launch(wm);
        }
    } else {
        serial_println!("[NEUXON-KERNEL] WARNING: No linear framebuffer provided by bootloader!");
    }

    // ------------------------------------------------------------------------
    // 10. Enable Hardware Interrupts & Enter Compositor Loop
    // ------------------------------------------------------------------------
    serial_println!("[NEUXON-KERNEL] Enabling CPU interrupts and launching NeuxonWM Compositor loop...");
    arch::x86_64::enable_interrupts();

    serial_println!("╔══════════════════════════════════════════════════════════════════╗");
    serial_println!("║ NEUXON OS 2.0 RUNNING: macOS DOCK & TOP BAR ACTIVE               ║");
    serial_println!("╚══════════════════════════════════════════════════════════════════╝");

    loop {
        // 1. Process asynchronous syscall ring submissions
        unsafe {
            ipc::ring_buffer::get_global_ring().dispatch_pending();
        }

        // 2. Poll input events and dispatch to Window Manager
        while let Some(key_event) = drivers::keyboard::pop_key_event() {
            if let Some(ref mut wm) = *gui::wm::WM.lock() {
                wm.handle_key_input(key_event);
            }
        }

        let mouse_state = drivers::mouse::get_mouse_state();
        if let Some(ref mut wm) = *gui::wm::WM.lock() {
            wm.handle_mouse_input(mouse_state);

            // 3. Render next frame
            let mut display_lock = gui::framebuffer::DISPLAY.lock();
            if let Some(ref mut display) = *display_lock {
                wm.compose(display, mouse_state);
            }
        }

        // 4. Halt CPU until next interrupt tick
        arch::x86_64::hlt();
    }
}

/// Fallback idle worker
fn idle_worker() {
    loop {
        arch::x86_64::hlt();
    }
}

/// Dynamic Allocation Error Handler
#[alloc_error_handler]
fn alloc_error_handler(layout: core::alloc::Layout) -> ! {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║ KERNEL PANIC: OUT OF MEMORY                              ║");
    serial_println!("╠══════════════════════════════════════════════════════════╣");
    serial_println!("║ Requested Layout: {:?}", layout);
    serial_println!("╚══════════════════════════════════════════════════════════╝");
    panic!("Out of heap memory: {:?}", layout);
}

/// Kernel Panic Handler
#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    serial_println!("╔══════════════════════════════════════════════════════════╗");
    serial_println!("║                     KERNEL PANIC                         ║");
    serial_println!("╠══════════════════════════════════════════════════════════╣");
    serial_println!("║ {}", info);
    serial_println!("╚══════════════════════════════════════════════════════════╝");

    arch::x86_64::disable_interrupts();
    loop {
        arch::x86_64::hlt();
    }
}
