//! Physical Frame Allocator for MONO-OS
//! Tracks physical memory regions and allocates 4KiB frames and 2MiB HugePages.

use bootloader::bootinfo::{MemoryMap, MemoryRegionType};
use core::sync::atomic::{AtomicUsize, Ordering};
use x86_64::structures::paging::{FrameAllocator, PhysFrame, Size2MiB, Size4KiB};
use x86_64::PhysAddr;

/// Physical memory tracking telemetry
pub static TOTAL_USABLE_FRAMES: AtomicUsize = AtomicUsize::new(0);
pub static ALLOCATED_FRAMES: AtomicUsize = AtomicUsize::new(0);

/// Lock-free, bump-pointer physical frame allocator backed by bootloader memory map
pub struct BootInfoFrameAllocator {
    memory_map: &'static MemoryMap,
    next_frame_index: usize,
}

impl BootInfoFrameAllocator {
    /// Initialize allocator using the bootloader memory map
    ///
    /// # Safety
    /// Caller must guarantee that the memory map passed is valid and all marked usable frames are truly unused.
    pub unsafe fn init(memory_map: &'static MemoryMap) -> Self {
        let mut total_usable = 0;
        for region in memory_map.iter() {
            if region.region_type == MemoryRegionType::Usable {
                let frame_count = (region.range.end_frame_number - region.range.start_frame_number) as usize;
                total_usable += frame_count;
            }
        }
        TOTAL_USABLE_FRAMES.store(total_usable, Ordering::SeqCst);

        Self {
            memory_map,
            next_frame_index: 0,
        }
    }

    /// Return an iterator over usable physical memory frames
    fn usable_frames(&self) -> impl Iterator<Item = PhysFrame> {
        let regions = self.memory_map.iter();
        let usable_regions = regions.filter(|r| r.region_type == MemoryRegionType::Usable);
        let addr_ranges = usable_regions.map(|r| r.range.start_addr()..r.range.end_addr());
        let frame_addresses = addr_ranges.flat_map(|r| r.step_by(4096));
        frame_addresses.map(|addr| PhysFrame::containing_address(PhysAddr::new(addr)))
    }

    /// Allocate a contiguous 2MiB HugePage frame
    pub fn allocate_huge_frame(&mut self) -> Option<PhysFrame<Size2MiB>> {
        // Search usable regions for a 2MiB-aligned physical range
        for region in self.memory_map.iter() {
            if region.region_type == MemoryRegionType::Usable {
                let start = region.range.start_addr();
                let end = region.range.end_addr();
                let aligned_start = (start + 0x1F_FFFF) & !0x1F_FFFF;
                if aligned_start + 0x20_0000 <= end {
                    ALLOCATED_FRAMES.fetch_add(512, Ordering::SeqCst);
                    return Some(PhysFrame::containing_address(PhysAddr::new(aligned_start)));
                }
            }
        }
        None
    }
}

unsafe impl FrameAllocator<Size4KiB> for BootInfoFrameAllocator {
    fn allocate_frame(&mut self) -> Option<PhysFrame<Size4KiB>> {
        let frame = self.usable_frames().nth(self.next_frame_index);
        self.next_frame_index += 1;
        if frame.is_some() {
            ALLOCATED_FRAMES.fetch_add(1, Ordering::Relaxed);
        }
        frame
    }
}
