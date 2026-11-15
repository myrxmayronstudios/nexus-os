//! Neuxon OS Persistent Desktop Widget Engine
//! Embeds live kernel telemetry, chrono matrix, VFS notes, and packet stream in desktop safe-zones.

pub mod telemetry;
pub mod chrono;
pub mod sticky_pad;
pub mod net_matrix;

use crate::gui::framebuffer::MonoDisplay;
use telemetry::TelemetryWidget;
use chrono::ChronoWidget;
use sticky_pad::StickyPadWidget;
use net_matrix::NetMatrixWidget;

pub struct WidgetManager {
    pub telemetry: TelemetryWidget,
    pub chrono: ChronoWidget,
    pub sticky_pad: StickyPadWidget,
    pub net_matrix: NetMatrixWidget,
}

impl WidgetManager {
    pub fn new(screen_width: usize, screen_height: usize) -> Self {
        // Safe-zones between Top Menu Bar (y=22) and Floating Dock (y=screen_height-50)
        let telemetry = TelemetryWidget::new(24, 30);
        let chrono = ChronoWidget::new(screen_width.saturating_sub(32 * 8 + 24), 30);
        let sticky_pad = StickyPadWidget::new(24, screen_height.saturating_sub(10 * 16 + 64));
        let net_matrix = NetMatrixWidget::new(
            screen_width.saturating_sub(44 * 8 + 24),
            screen_height.saturating_sub(11 * 16 + 64),
        );

        Self {
            telemetry,
            chrono,
            sticky_pad,
            net_matrix,
        }
    }

    pub fn render_all(&self, display: &mut MonoDisplay) {
        self.telemetry.render(display);
        self.chrono.render(display);
        self.sticky_pad.render(display);
        self.net_matrix.render(display);
    }
}
