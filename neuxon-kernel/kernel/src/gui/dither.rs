//! 1-Bit Bayer Ordered Dithering Engine for MONO-OS
//! Converts 24-bit RGB, 8-bit grayscale, or intensity levels into pure 1-bit Monochrome (#000000 / #FFFFFF).

/// 4x4 Bayer Dithering Matrix (Values 0..255)
pub const BAYER_4X4: [[u8; 4]; 4] = [
    [  0, 128,  32, 160],
    [192,  64, 224,  96],
    [ 48, 176,  16, 144],
    [240, 112, 208,  80],
];

/// 8x8 Bayer Dithering Matrix (Values 0..255 for ultra-smooth gradients)
pub const BAYER_8X8: [[u8; 8]; 8] = [
    [  0,  32,   8,  40,   2,  34,  10,  42],
    [ 48,  16,  56,  24,  50,  18,  58,  26],
    [ 12,  44,   4,  36,  14,  46,   6,  38],
    [ 60,  28,  52,  20,  62,  30,  54,  22],
    [  3,  35,  11,  43,   1,  33,   9,  41],
    [ 51,  19,  59,  27,  49,  17,  57,  25],
    [ 15,  47,   7,  39,  13,  45,   5,  37],
    [ 63,  31,  55,  23,  61,  29,  53,  21],
];

/// Scale 0..63 matrix to 0..255
#[inline(always)]
fn bayer_8x8_val(x: usize, y: usize) -> u8 {
    (BAYER_8X8[y % 8][x % 8] << 2) | (BAYER_8X8[y % 8][x % 8] >> 4)
}

/// Convert 24-bit RGB to 8-bit perceived luminance (ITU-R BT.601)
#[inline(always)]
pub fn rgb_to_luminance(r: u8, g: u8, b: u8) -> u8 {
    ((r as u32 * 299 + g as u32 * 587 + b as u32 * 114) / 1000) as u8
}

/// Dither an 8-bit luminance level using 4x4 Bayer Matrix
/// Returns true for White (#FFFFFF), false for Black (#000000)
#[inline(always)]
pub fn dither_4x4(x: usize, y: usize, luminance: u8) -> bool {
    let threshold = BAYER_4X4[y & 3][x & 3];
    luminance > threshold
}

/// Dither an 8-bit luminance level using 8x8 Bayer Matrix
/// Returns true for White (#FFFFFF), false for Black (#000000)
#[inline(always)]
pub fn dither_8x8(x: usize, y: usize, luminance: u8) -> bool {
    let threshold = bayer_8x8_val(x, y);
    luminance > threshold
}

/// Dither an RGB pixel at coordinate (x, y) into 1-bit monochrome
#[inline(always)]
pub fn dither_pixel_rgb(x: usize, y: usize, r: u8, g: u8, b: u8) -> bool {
    let lum = rgb_to_luminance(r, g, b);
    dither_8x8(x, y, lum)
}

/// Preset Dither Densities for UI shading (0: Black, 16: White)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShadingPattern {
    SolidBlack,   // 0%
    UltraLight,   // 12.5%
    Light,        // 25% (░)
    Medium,       // 50% (▒)
    Dark,         // 75% (▓)
    UltraDark,    // 87.5%
    SolidWhite,   // 100% (█)
}

impl ShadingPattern {
    #[inline(always)]
    pub fn is_white(self, x: usize, y: usize) -> bool {
        match self {
            Self::SolidBlack => false,
            Self::UltraLight => dither_4x4(x, y, 32),
            Self::Light => (x + y) % 4 == 0,
            Self::Medium => (x ^ y) & 1 == 0,
            Self::Dark => (x + y) % 4 != 0,
            Self::UltraDark => dither_4x4(x, y, 224),
            Self::SolidWhite => true,
        }
    }
}
