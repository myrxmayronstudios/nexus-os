/*
 * MONO-OS Kernel Linker Script (x86_64)
 * Enforces strict section isolation, page alignment, and NX boundaries.
 */

ENTRY(_start)

SECTIONS
{
    /* Bootloader loads kernel starting at 1MiB physical / mapped higher half */
    . = 0x100000;

    .boot : ALIGN(4K)
    {
        KEEP(*(.boot .boot.*))
    }

    .rodata : ALIGN(4K)
    {
        __rodata_start = .;
        *(.rodata .rodata.*)
        . = ALIGN(4K);
        __rodata_end = .;
    }

    .text : ALIGN(4K)
    {
        __text_start = .;
        *(.text .text.*)
        . = ALIGN(4K);
        __text_end = .;
    }

    .data : ALIGN(4K)
    {
        __data_start = .;
        *(.data .data.*)
        *(.got .got.*)
        . = ALIGN(4K);
        __data_end = .;
    }

    .bss : ALIGN(4K)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4K);
        __bss_end = .;
    }

    /* Discard unused metadata to keep binary lean */
    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame)
        *(.note.GNU-stack)
    }
}
