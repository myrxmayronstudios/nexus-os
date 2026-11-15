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
            b"NeuxonOS 3.5.0-exokernel (16-Bit Obsidian & Silver Edition)\n",
        );
        vfs.write_file(
            "/sys/kernel_cmdline",
            b"BOOT_IMAGE=/boot/vmlinuz root=PARTUUID=neuxon-01 ro quiet guard=active hidpi=2x 16bit=true dock=macos\n",
        );
        vfs.write_file(
            "/sys/notes.txt",
            b"=== NEUXON OS 3.5 PERSISTENT WORKSPACE ===\n- Architecture: 16-Bit Obsidian & Silver Exokernel\n- NeuxonGuard: Autonomous OODA Supervisor (PID 1 NeuxonDoctor)\n- Display Server: 120fps NeuxonWM with Spring Physics & Clamping\n- Syscall Engine: Lock-Free Dual-Ring Buffer (0.0002ms Latency)\n",
        );
        vfs.write_file(
            "/sys/heal.log",
            b"[BOOT] NeuxonGuard Stage-0/Stage-1 boot diagnostic completed with 0 errors.\n",
        );
        vfs.write_file(
            "/home/user/welcome.txt",
            b"Welcome to Neuxon OS 3.5.\nExperience high-resolution 16-bit obsidian/silver typography & autonomous self-healing!\n",
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
