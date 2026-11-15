//! Memory Management Subsystem for MONO-OS
//! Physical frames, 4-level paging mapper, and zero-fragmentation slab allocation.

pub mod frame;
pub mod page_table;
pub mod slab;

use bootloader::BootInfo;
use x86_64::structures::paging::{Page, PageTableFlags, Size4KiB};
use x86_64::VirtAddr;

/// Virtual address start of the kernel heap (64 MiB allocated at 0xFFFF_9000_0000_0000)
pub const HEAP_START: usize = 0xFFFF_9000_0000_0000;
pub const HEAP_SIZE: usize = 64 * 1024 * 1024; // 64 MiB

/// Initialize the complete kernel memory architecture:
/// 1. Initialize physical frame allocator from bootloader memory map.
/// 2. Initialize 4-level paging mapper using physical memory offset.
/// 3. Map virtual heap pages to physical frames.
/// 4. Initialize zero-fragmentation Slab allocator.
pub fn init(boot_info: &'static BootInfo) {
    let phys_mem_offset = VirtAddr::new(boot_info.physical_memory_offset);

    // SAFETY: Bootloader guarantees valid physical memory offset and usable memory map
    let mut mapper = unsafe { page_table::init_mapper(phys_mem_offset) };
    let mut frame_allocator = unsafe { frame::BootInfoFrameAllocator::init(&boot_info.memory_map) };

    // Map heap virtual pages
    let page_range = {
        let heap_start = VirtAddr::new(HEAP_START as u64);
        let heap_end = heap_start + HEAP_SIZE - 1u64;
        let heap_start_page = Page::<Size4KiB>::containing_address(heap_start);
        let heap_end_page = Page::<Size4KiB>::containing_address(heap_end);
        Page::range_inclusive(heap_start_page, heap_end_page)
    };

    let flags = PageTableFlags::PRESENT | PageTableFlags::WRITABLE | PageTableFlags::NO_EXECUTE;

    for page in page_range {
        use x86_64::structures::paging::FrameAllocator;
        let frame = frame_allocator
            .allocate_frame()
            .expect("Out of physical memory while initializing kernel heap");
        // SAFETY: Mapping newly allocated physical frame to distinct heap virtual address
        unsafe {
            page_table::map_page(&mut mapper, page, frame, flags, &mut frame_allocator)
                .expect("Failed to map heap page");
        }
    }

    // Initialize global slab allocator with the mapped heap memory
    // SAFETY: The heap virtual range has been mapped to physical frames and is unused
    unsafe {
        slab::ALLOCATOR.inner.lock().init(HEAP_START, HEAP_SIZE);
    }
}
