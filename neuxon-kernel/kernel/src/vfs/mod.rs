//! Minimal Kernel In-Memory Virtual File System (VFS) for Neuxon OS
//! Provides thread-safe reading, writing, and node inspection for /sys and user nodes.

use alloc::collections::BTreeMap;
use alloc::string::String;
use alloc::vec::Vec;
use spin::Mutex;

#[derive(Debug, Clone)]
pub struct VfsNode {
    pub name: String,
    pub is_dir: bool,
    pub data: Vec<u8>,
}

pub struct VirtualFileSystem {
    nodes: BTreeMap<String, VfsNode>,
}

impl VirtualFileSystem {
    pub fn new() -> Self {
        let mut vfs = Self {
            nodes: BTreeMap::new(),
        };

        // Populate initial Neuxon OS kernel virtual files
        vfs.write_file(
            "/sys/version",
            b"NeuxonOS 1.0.0-exokernel (Zero-Latency Rust SMP Microkernel)\n",
        );
        vfs.write_file(
            "/sys/kernel_cmdline",
            b"BOOT_IMAGE=/boot/vmlinuz root=PARTUUID=neuxon-01 ro quiet dock=macos 1bit=true\n",
        );
        vfs.write_file(
            "/sys/notes.txt",
            b"=== NEUXON OS PERSISTENT DESKTOP NOTES ===\n- Architecture: 1-Bit Hybrid Exokernel (Rust)\n- Compositor: NeuxonWM (macOS Character Dock + Top Bar)\n- Syscall Ring: Lock-Free Asynchronous MonoRing\n- Window Controls: Top-Left Character Traffic Lights\n",
        );
        vfs.write_file(
            "/home/user/welcome.txt",
            b"Welcome to Neuxon OS 2.0.\nExperience high-performance 1-bit typography & macOS ergonomics!\n",
        );

        vfs
    }

    pub fn read_file(&self, path: &str) -> Option<Vec<u8>> {
        self.nodes.get(path).map(|n| n.data.clone())
    }

    pub fn write_file(&mut self, path: &str, content: &[u8]) {
        self.nodes.insert(
            String::from(path),
            VfsNode {
                name: String::from(path),
                is_dir: false,
                data: content.to_vec(),
            },
        );
    }

    pub fn list_dir(&self, prefix: &str) -> Vec<String> {
        let mut list = Vec::new();
        for key in self.nodes.keys() {
            if key.starts_with(prefix) {
                list.push(key.clone());
            }
        }
        list
    }
}

pub static VFS: Mutex<Option<VirtualFileSystem>> = Mutex::new(None);

pub fn init() {
    *VFS.lock() = Some(VirtualFileSystem::new());
    crate::arch::x86_64::serial_println!("[NeuxonVFS] In-Memory Virtual File System initialized.");
}

pub fn read(path: &str) -> Option<Vec<u8>> {
    VFS.lock().as_ref().and_then(|v| v.read_file(path))
}

pub fn write(path: &str, data: &[u8]) {
    if let Some(ref mut v) = *VFS.lock() {
        v.write_file(path, data);
    }
}
