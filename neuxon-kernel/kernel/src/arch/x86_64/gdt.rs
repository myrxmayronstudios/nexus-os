//! Global Descriptor Table (GDT) & Task State Segment (TSS)
//! Configures privilege rings (Kernel Ring 0 / User Ring 3) and dedicated IST stacks.

use lazy_static::lazy_static;
use x86_64::structures::gdt::{Descriptor, GlobalDescriptorTable, SegmentSelector};
use x86_64::structures::tss::TaskStateSegment;
use x86_64::VirtAddr;

/// Index in the Interrupt Stack Table used exclusively for Double Fault exceptions
pub const DOUBLE_FAULT_IST_INDEX: u16 = 0;

/// Size of the dedicated stack allocated for double fault handling (20 KiB)
const STACK_SIZE: usize = 4096 * 5;

lazy_static! {
    /// Global Task State Segment holding dedicated interrupt stacks
    static ref TSS: TaskStateSegment = {
        let mut tss = TaskStateSegment::new();
        // Allocate a dedicated static stack for double faults so stack overflows can be safely handled
        static mut DOUBLE_FAULT_STACK: [u8; STACK_SIZE] = [0; STACK_SIZE];

        // SAFETY: Stack pointer is valid, non-overlapping, and aligned
        let stack_start = VirtAddr::from_ptr(unsafe { &DOUBLE_FAULT_STACK });
        let stack_end = stack_start + STACK_SIZE;
        tss.interrupt_stack_table[DOUBLE_FAULT_IST_INDEX as usize] = stack_end;
        tss
    };

    /// GDT holding kernel code, kernel data, user code, user data, and TSS descriptors
    static ref GDT: (GlobalDescriptorTable, Selectors) = {
        let mut gdt = GlobalDescriptorTable::new();
        let kernel_code_selector = gdt.add_entry(Descriptor::kernel_code_segment());
        let kernel_data_selector = gdt.add_entry(Descriptor::kernel_data_segment());
        let user_data_selector = gdt.add_entry(Descriptor::user_data_segment());
        let user_code_selector = gdt.add_entry(Descriptor::user_code_segment());
        let tss_selector = gdt.add_entry(Descriptor::tss_segment(&TSS));
        (
            gdt,
            Selectors {
                kernel_code_selector,
                kernel_data_selector,
                user_code_selector,
                user_data_selector,
                tss_selector,
            },
        )
    };
}

/// Segment selectors created in the GDT
#[derive(Debug, Clone, Copy)]
pub struct Selectors {
    pub kernel_code_selector: SegmentSelector,
    pub kernel_data_selector: SegmentSelector,
    pub user_code_selector: SegmentSelector,
    pub user_data_selector: SegmentSelector,
    pub tss_selector: SegmentSelector,
}

/// Initialize and load the GDT, TSS, and segment registers
pub fn init() {
    use x86_64::instructions::segmentation::{Segment, CS, DS, ES, SS};
    use x86_64::instructions::tables::load_tss;

    GDT.0.load();
    // SAFETY: Selectors correspond exactly to the table loaded above
    unsafe {
        CS::set_reg(GDT.1.kernel_code_selector);
        DS::set_reg(GDT.1.kernel_data_selector);
        ES::set_reg(GDT.1.kernel_data_selector);
        SS::set_reg(GDT.1.kernel_data_selector);
        load_tss(GDT.1.tss_selector);
    }
}

/// Retrieve the active kernel and user segment selectors
pub fn get_selectors() -> Selectors {
    GDT.1
}
