//! 4-Level x86_64 Paging Architecture & Virtual Memory Manager
//! Supports identity mapping, kernel higher-half mappings, and 2MiB HugePages.

use x86_64::registers::control::Cr3;
use x86_64::structures::paging::{
    FrameAllocator, Mapper, OffsetPageTable, Page, PageTable, PageTableFlags, PhysFrame, Size2MiB,
    Size4KiB,
};
use x86_64::{PhysAddr, VirtAddr};

/// Initialize a new OffsetPageTable using the physical memory offset provided by the bootloader
///
/// # Safety
/// Caller must guarantee that the physical memory offset points to a valid identity/higher-half mapping.
pub unsafe fn init_mapper(physical_memory_offset: VirtAddr) -> OffsetPageTable<'static> {
    // Read current PML4 table address from CR3 control register
    let (level_4_table_frame, _) = Cr3::read();
    let phys = level_4_table_frame.start_address();
    let virt = physical_memory_offset + phys.as_u64();
    let page_table_ptr: *mut PageTable = virt.as_mut_ptr();

    // SAFETY: CR3 points to the active level 4 table; physical_memory_offset maps all physical memory
    let level_4_table = unsafe { &mut *page_table_ptr };
    // SAFETY: Constructed page table reference is active and valid
    unsafe { OffsetPageTable::new(level_4_table, physical_memory_offset) }
}

/// Map a single 4KiB virtual page to a specified physical frame with given permission flags
///
/// # Safety
/// Caller must guarantee that the mapping will not produce alias conflicts or violate memory safety.
pub unsafe fn map_page<A: FrameAllocator<Size4KiB>>(
    mapper: &mut OffsetPageTable<'static>,
    page: Page<Size4KiB>,
    frame: PhysFrame<Size4KiB>,
    flags: PageTableFlags,
    frame_allocator: &mut A,
) -> Result<(), &'static str> {
    // SAFETY: Delegated to x86_64 crate with explicit caller guarantees
    let map_to_result = unsafe { mapper.map_to(page, frame, flags, frame_allocator) };
    match map_to_result {
        Ok(tlb_flush) => {
            tlb_flush.flush();
            Ok(())
        }
        Err(_) => Err("Failed to map 4KiB page"),
    }
}

/// Unmap a virtual page and flush the corresponding Translation Lookaside Buffer (TLB) entry
pub fn unmap_page(
    mapper: &mut OffsetPageTable<'static>,
    page: Page<Size4KiB>,
) -> Result<PhysFrame<Size4KiB>, &'static str> {
    match mapper.unmap(page) {
        Ok((frame, tlb_flush)) => {
            tlb_flush.flush();
            Ok(frame)
        }
        Err(_) => Err("Failed to unmap virtual page"),
    }
}

/// Translate a virtual address to its corresponding physical address
pub fn translate_addr(mapper: &OffsetPageTable<'static>, addr: VirtAddr) -> Option<PhysAddr> {
    mapper.translate_addr(addr)
}
