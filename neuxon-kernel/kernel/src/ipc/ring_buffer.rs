//! Lock-Free Asynchronous Syscall Ring Buffer ("MonoRing")
//! High-performance, zero-copy shared-memory IPC architecture inspired by io_uring.
//! Eliminates synchronous CPU trap stalls (int 0x80 / syscall) for GUI and user processes.

use core::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// Default capacity for submission and completion queue rings (must be power of two)
pub const RING_ENTRIES: usize = 256;
pub const RING_MASK: u32 = (RING_ENTRIES as u32) - 1;

/// Monotonic counter tracking processed asynchronous syscall operations
pub static TOTAL_SYSCALL_OPS: AtomicU64 = AtomicU64::new(0);

// ============================================================================
// Syscall Opcodes
// ============================================================================

pub const OP_NOP: u8 = 0;
pub const OP_READ: u8 = 1;
pub const OP_WRITE: u8 = 2;
pub const OP_MMAP: u8 = 3;
pub const OP_MUNMAP: u8 = 4;
pub const OP_FRAMEBUFFER_FLUSH: u8 = 5;
pub const OP_YIELD: u8 = 6;
pub const OP_POLL: u8 = 7;
pub const OP_IPC_SEND: u8 = 8;
pub const OP_IPC_RECV: u8 = 9;
pub const OP_FUTEX_WAIT: u8 = 10;
pub const OP_FUTEX_WAKE: u8 = 11;

// ============================================================================
// Submission & Completion Queue Entries
// ============================================================================

/// Submission Queue Entry (SQE) — Exactly 64 bytes (1 CPU cacheline)
#[repr(C, align(64))]
#[derive(Debug, Clone, Copy)]
pub struct SubmissionQueueEntry {
    /// Asynchronous syscall operation code
    pub opcode: u8,
    /// Submission flags
    pub flags: u8,
    /// I/O priority
    pub ioprio: u16,
    /// File descriptor or device handle
    pub fd: i32,
    /// Virtual buffer pointer or offset
    pub addr: u64,
    /// Buffer length or byte count
    pub len: u32,
    /// Target file/device offset
    pub offset: u64,
    /// Caller-specified identifier returned verbatim in CompletionQueueEntry
    pub user_data: u64,
    /// Padding to enforce strict 64-byte alignment
    pub _reserved: [u8; 24],
}

impl SubmissionQueueEntry {
    pub const fn empty() -> Self {
        Self {
            opcode: OP_NOP,
            flags: 0,
            ioprio: 0,
            fd: 0,
            addr: 0,
            len: 0,
            offset: 0,
            user_data: 0,
            _reserved: [0; 24],
        }
    }
}

/// Completion Queue Entry (CQE) — Exactly 16 bytes
#[repr(C, align(16))]
#[derive(Debug, Clone, Copy)]
pub struct CompletionQueueEntry {
    /// Identifier passed from corresponding SubmissionQueueEntry
    pub user_data: u64,
    /// Result code (positive byte count/value or negative error code)
    pub res: i32,
    /// Completion status flags
    pub flags: u32,
}

impl CompletionQueueEntry {
    pub const fn empty() -> Self {
        Self {
            user_data: 0,
            res: 0,
            flags: 0,
        }
    }
}

// ============================================================================
// Lock-Free Ring Data Structures
// ============================================================================

/// Cacheline-isolated atomic index wrapper preventing false sharing
#[repr(align(64))]
pub struct CachelineIndex {
    pub value: AtomicU32,
}

impl CachelineIndex {
    pub const fn new(init: u32) -> Self {
        Self {
            value: AtomicU32::new(init),
        }
    }
}

/// Shared-memory Submission Queue
pub struct SubmissionQueue {
    pub head: CachelineIndex,
    pub tail: CachelineIndex,
    pub entries: [SubmissionQueueEntry; RING_ENTRIES],
}

impl SubmissionQueue {
    pub const fn new() -> Self {
        Self {
            head: CachelineIndex::new(0),
            tail: CachelineIndex::new(0),
            entries: [SubmissionQueueEntry::empty(); RING_ENTRIES],
        }
    }

    /// User-space submission: enqueue a new request without kernel trap
    pub fn submit(&mut self, sqe: SubmissionQueueEntry) -> Result<(), &'static str> {
        let head = self.head.value.load(Ordering::Acquire);
        let tail = self.tail.value.load(Ordering::Relaxed);

        if tail.wrapping_sub(head) >= (RING_ENTRIES as u32) {
            return Err("Submission queue ring full");
        }

        let index = (tail & RING_MASK) as usize;
        self.entries[index] = sqe;

        // Release tail to kernel consumer with memory fence
        self.tail.value.store(tail.wrapping_add(1), Ordering::Release);
        Ok(())
    }
}

/// Shared-memory Completion Queue
pub struct CompletionQueue {
    pub head: CachelineIndex,
    pub tail: CachelineIndex,
    pub entries: [CompletionQueueEntry; RING_ENTRIES],
}

impl CompletionQueue {
    pub const fn new() -> Self {
        Self {
            head: CachelineIndex::new(0),
            tail: CachelineIndex::new(0),
            entries: [CompletionQueueEntry::empty(); RING_ENTRIES],
        }
    }

    /// Kernel completion: publish result entry to user space
    pub fn complete(&mut self, cqe: CompletionQueueEntry) -> Result<(), &'static str> {
        let head = self.head.value.load(Ordering::Acquire);
        let tail = self.tail.value.load(Ordering::Relaxed);

        if tail.wrapping_sub(head) >= (RING_ENTRIES as u32) {
            return Err("Completion queue ring full");
        }

        let index = (tail & RING_MASK) as usize;
        self.entries[index] = cqe;

        self.tail.value.store(tail.wrapping_add(1), Ordering::Release);
        Ok(())
    }

    /// User-space completion consumer: harvest completed syscall results
    pub fn pop(&mut self) -> Option<CompletionQueueEntry> {
        let head = self.head.value.load(Ordering::Relaxed);
        let tail = self.tail.value.load(Ordering::Acquire);

        if head == tail {
            return None;
        }

        let index = (head & RING_MASK) as usize;
        let cqe = self.entries[index];

        self.head.value.store(head.wrapping_add(1), Ordering::Release);
        Some(cqe)
    }
}

/// Combined bidirectional MonoRing engine
pub struct MonoRing {
    pub sq: SubmissionQueue,
    pub cq: CompletionQueue,
}

impl MonoRing {
    pub const fn new() -> Self {
        Self {
            sq: SubmissionQueue::new(),
            cq: CompletionQueue::new(),
        }
    }

    /// Kernel dispatch loop: process pending user requests without context switch
    pub fn dispatch_pending(&mut self) -> usize {
        let mut processed = 0;

        loop {
            let sq_head = self.sq.head.value.load(Ordering::Relaxed);
            let sq_tail = self.sq.tail.value.load(Ordering::Acquire);

            if sq_head == sq_tail {
                break;
            }

            let sq_index = (sq_head & RING_MASK) as usize;
            let sqe = self.sq.entries[sq_index];

            // Execute asynchronous kernel syscall
            let cqe = self.execute_syscall(&sqe);

            // Record completion
            let _ = self.cq.complete(cqe);

            self.sq.head.value.store(sq_head.wrapping_add(1), Ordering::Release);
            processed += 1;
            TOTAL_SYSCALL_OPS.fetch_add(1, Ordering::Relaxed);
        }

        processed
    }

    /// Internal non-blocking syscall executor
    fn execute_syscall(&self, sqe: &SubmissionQueueEntry) -> CompletionQueueEntry {
        match sqe.opcode {
            OP_NOP => CompletionQueueEntry {
                user_data: sqe.user_data,
                res: 0,
                flags: 0,
            },
            OP_YIELD => {
                CompletionQueueEntry {
                    user_data: sqe.user_data,
                    res: 0,
                    flags: 0,
                }
            }
            OP_WRITE => {
                // Emulated zero-latency write operation (e.g. standard output / virtual terminal)
                CompletionQueueEntry {
                    user_data: sqe.user_data,
                    res: sqe.len as i32,
                    flags: 0,
                }
            }
            OP_FRAMEBUFFER_FLUSH => {
                // Signal display compositor that damaged rectangle is ready for swap
                CompletionQueueEntry {
                    user_data: sqe.user_data,
                    res: 0,
                    flags: 0,
                }
            }
            _ => CompletionQueueEntry {
                user_data: sqe.user_data,
                res: -38, // -ENOSYS (Function not implemented)
                flags: 0,
            },
        }
    }
}

/// Global system syscall ring instance
pub static mut GLOBAL_MONO_RING: MonoRing = MonoRing::new();

/// Initialize global asynchronous syscall ring
pub fn init() {
    // SAFETY: Initializing single global ring instance during uniprocessor early boot
    unsafe {
        GLOBAL_MONO_RING = MonoRing::new();
    }
}

/// Retrieve mutable reference to the global syscall ring
///
/// # Safety
/// Caller must ensure synchronization when accessing from multiple thread contexts.
pub unsafe fn get_global_ring() -> &'static mut MonoRing {
    // SAFETY: Guaranteed by caller invariants
    unsafe { &mut GLOBAL_MONO_RING }
}
