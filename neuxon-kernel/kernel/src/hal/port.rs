//! Type-safe Hardware Port I/O
//! Provides safe and isolated interfaces for x86_64 CPU port-mapped I/O.

use core::arch::asm;
use core::marker::PhantomData;

/// Trait implemented by port-accessible data primitives (u8, u16, u32)
pub trait PortReadWrite {
    /// Read value from specified 16-bit hardware port address
    ///
    /// # Safety
    /// Reading from arbitrary hardware I/O ports can trigger device side-effects.
    unsafe fn read_from_port(port: u16) -> Self;

    /// Write value to specified 16-bit hardware port address
    ///
    /// # Safety
    /// Writing to arbitrary hardware I/O ports can alter device controller state.
    unsafe fn write_to_port(port: u16, value: Self);
}

impl PortReadWrite for u8 {
    #[inline(always)]
    unsafe fn read_from_port(port: u16) -> Self {
        let value: u8;
        // SAFETY: Caller guarantees that port is valid and read operation is safe
        unsafe {
            asm!(
                "in al, dx",
                in("dx") port,
                out("al") value,
                options(nomem, nostack, preserves_flags)
            );
        }
        value
    }

    #[inline(always)]
    unsafe fn write_to_port(port: u16, value: Self) {
        // SAFETY: Caller guarantees that port is valid and write operation is safe
        unsafe {
            asm!(
                "out dx, al",
                in("dx") port,
                in("al") value,
                options(nomem, nostack, preserves_flags)
            );
        }
    }
}

impl PortReadWrite for u16 {
    #[inline(always)]
    unsafe fn read_from_port(port: u16) -> Self {
        let value: u16;
        // SAFETY: Caller guarantees that port is valid and read operation is safe
        unsafe {
            asm!(
                "in ax, dx",
                in("dx") port,
                out("ax") value,
                options(nomem, nostack, preserves_flags)
            );
        }
        value
    }

    #[inline(always)]
    unsafe fn write_to_port(port: u16, value: Self) {
        // SAFETY: Caller guarantees that port is valid and write operation is safe
        unsafe {
            asm!(
                "out dx, ax",
                in("dx") port,
                in("ax") value,
                options(nomem, nostack, preserves_flags)
            );
        }
    }
}

impl PortReadWrite for u32 {
    #[inline(always)]
    unsafe fn read_from_port(port: u16) -> Self {
        let value: u32;
        // SAFETY: Caller guarantees that port is valid and read operation is safe
        unsafe {
            asm!(
                "in eax, dx",
                in("dx") port,
                out("eax") value,
                options(nomem, nostack, preserves_flags)
            );
        }
        value
    }

    #[inline(always)]
    unsafe fn write_to_port(port: u16, value: Self) {
        // SAFETY: Caller guarantees that port is valid and write operation is safe
        unsafe {
            asm!(
                "out dx, eax",
                in("dx") port,
                in("eax") value,
                options(nomem, nostack, preserves_flags)
            );
        }
    }
}

/// Type-safe, isolated hardware I/O port representation
#[derive(Debug, Clone, Copy)]
pub struct Port<T: PortReadWrite> {
    port_address: u16,
    _phantom: PhantomData<T>,
}

impl<T: PortReadWrite> Port<T> {
    /// Instantiate a type-safe port at given address
    pub const fn new(port_address: u16) -> Self {
        Self {
            port_address,
            _phantom: PhantomData,
        }
    }

    /// Read value from port
    ///
    /// # Safety
    /// Caller must ensure that reading from this port does not violate hardware invariants.
    #[inline(always)]
    pub unsafe fn read(&self) -> T {
        // SAFETY: Delegated to PortReadWrite implementation
        unsafe { T::read_from_port(self.port_address) }
    }

    /// Write value to port
    ///
    /// # Safety
    /// Caller must ensure that writing this value does not corrupt device controller state.
    #[inline(always)]
    pub unsafe fn write(&mut self, value: T) {
        // SAFETY: Delegated to PortReadWrite implementation
        unsafe { T::write_to_port(self.port_address, value) }
    }
}

/// Microsecond I/O wait delay using the legacy POST diagnostic port (0x80)
#[inline(always)]
pub fn io_wait() {
    let mut unused_port = Port::<u8>::new(0x80);
    // SAFETY: Writing 0 to the unused port 0x80 produces a deterministic ~1-2us bus cycle delay
    unsafe {
        unused_port.write(0);
    }
}
