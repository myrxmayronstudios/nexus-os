//! Zero-Fragmentation Slab & Object Allocator for MONO-OS
//! Implements `core::alloc::GlobalAlloc` with fixed-size power-of-two slab bins.

use core::alloc::{GlobalAlloc, Layout};
use core::ptr::{self, NonNull};
use core::sync::atomic::{AtomicUsize, Ordering};
use spin::Mutex;

/// Number of slab bins: 32, 64, 128, 256, 512, 1024, 2048, 4096 bytes
const SLAB_SIZES: [usize; 8] = [32, 64, 128, 256, 512, 1024, 2048, 4096];

/// Telemetry metrics for active heap memory
pub static HEAP_ALLOCATED_BYTES: AtomicUsize = AtomicUsize::new(0);

/// Free-list node embedded within unused slab slots
struct ListNode {
    next: Option<&'static mut ListNode>,
}

/// A single slab bin managing allocations for a specific power-of-two byte size
struct SlabBin {
    block_size: usize,
    free_list: Option<&'static mut ListNode>,
}

impl SlabBin {
    const fn new(block_size: usize) -> Self {
        Self {
            block_size,
            free_list: None,
        }
    }

    /// Allocate a block from the slab's free list
    fn allocate(&mut self) -> Option<NonNull<u8>> {
        self.free_list.take().map(|node| {
            self.free_list = node.next.take();
            NonNull::new(node as *mut ListNode as *mut u8).unwrap()
        })
    }

    /// Deallocate a block and prepend it back to the free list
    ///
    /// # Safety
    /// Caller must ensure `ptr` points to a block previously allocated from this slab.
    unsafe fn deallocate(&mut self, ptr: NonNull<u8>) {
        let node_ptr = ptr.as_ptr() as *mut ListNode;
        // SAFETY: Node pointer is non-null, aligned, and previously owned by this slab
        unsafe {
            node_ptr.write(ListNode {
                next: self.free_list.take(),
            });
            self.free_list = Some(&mut *node_ptr);
        }
    }

    /// Populate free list with newly mapped page blocks
    ///
    /// # Safety
    /// Memory range `start..start+size` must be valid, mapped, and unused.
    unsafe fn add_memory(&mut self, start: usize, size: usize) {
        let count = size / self.block_size;
        for i in 0..count {
            let block_addr = start + (i * self.block_size);
            // SAFETY: Block addresses are within the provided valid memory range
            unsafe {
                self.deallocate(NonNull::new_unchecked(block_addr as *mut u8));
            }
        }
    }
}

/// Thread-safe Global Allocator wrapper
pub struct Locked<A> {
    inner: Mutex<A>,
}

impl<A> Locked<A> {
    pub const fn new(inner: A) -> Self {
        Self {
            inner: Mutex::new(inner),
        }
    }
}

/// The core Slab Allocator holding all power-of-two size bins
pub struct SlabAllocator {
    bins: [SlabBin; 8],
    fallback_heap_start: usize,
    fallback_heap_end: usize,
    fallback_bump_ptr: usize,
}

impl SlabAllocator {
    pub const fn new() -> Self {
        Self {
            bins: [
                SlabBin::new(32),
                SlabBin::new(64),
                SlabBin::new(128),
                SlabBin::new(256),
                SlabBin::new(512),
                SlabBin::new(1024),
                SlabBin::new(2048),
                SlabBin::new(4096),
            ],
            fallback_heap_start: 0,
            fallback_heap_end: 0,
            fallback_bump_ptr: 0,
        }
    }

    /// Initialize slab allocator with backing virtual memory region
    ///
    /// # Safety
    /// Memory region `heap_start..heap_start + heap_size` must be mapped and exclusively owned.
    pub unsafe fn init(&mut self, heap_start: usize, heap_size: usize) {
        let half_size = heap_size / 2;
        let slab_region_size = half_size / SLAB_SIZES.len();

        // Populate initial slab memory pools
        for (i, bin) in self.bins.iter_mut().enumerate() {
            let start = heap_start + (i * slab_region_size);
            // SAFETY: Region is distinct, mapped, and non-overlapping
            unsafe {
                bin.add_memory(start, slab_region_size);
            }
        }

        // Remaining half used as bump fallback for large allocations (>4KiB)
        self.fallback_heap_start = heap_start + half_size;
        self.fallback_heap_end = heap_start + heap_size;
        self.fallback_bump_ptr = self.fallback_heap_start;
    }

    /// Select the appropriate slab bin index for a requested layout
    fn bin_index(layout: Layout) -> Option<usize> {
        let size = layout.size().max(layout.align());
        SLAB_SIZES.iter().position(|&s| s >= size)
    }
}

unsafe impl GlobalAlloc for Locked<SlabAllocator> {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let mut allocator = self.inner.lock();

        if let Some(index) = SlabAllocator::bin_index(layout) {
            if let Some(ptr) = allocator.bins[index].allocate() {
                HEAP_ALLOCATED_BYTES.fetch_add(allocator.bins[index].block_size, Ordering::Relaxed);
                return ptr.as_ptr();
            }
        }

        // Large allocation fallback (bump allocation from reserved region)
        let align = layout.align();
        let size = layout.size();
        let current_ptr = (allocator.fallback_bump_ptr + align - 1) & !(align - 1);
        let next_ptr = current_ptr + size;

        if next_ptr <= allocator.fallback_heap_end {
            allocator.fallback_bump_ptr = next_ptr;
            HEAP_ALLOCATED_BYTES.fetch_add(size, Ordering::Relaxed);
            current_ptr as *mut u8
        } else {
            ptr::null_mut()
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if ptr.is_null() {
            return;
        }

        let mut allocator = self.inner.lock();
        if let Some(index) = SlabAllocator::bin_index(layout) {
            let non_null = NonNull::new(ptr).unwrap();
            // SAFETY: Verified non-null pointer released to its corresponding slab bin
            unsafe {
                allocator.bins[index].deallocate(non_null);
            }
            HEAP_ALLOCATED_BYTES.fetch_sub(allocator.bins[index].block_size, Ordering::Relaxed);
        } else {
            // Large fallback allocations are retained or freed via page-table unmap
            HEAP_ALLOCATED_BYTES.fetch_sub(layout.size(), Ordering::Relaxed);
        }
    }
}

#[global_allocator]
pub static ALLOCATOR: Locked<SlabAllocator> = Locked::new(SlabAllocator::new());
