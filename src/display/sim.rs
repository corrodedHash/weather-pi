use crate::effects::noop_display::NoopDisplay;
use embedded_graphics::pixelcolor::BinaryColor;
use embedded_graphics_simulator::{
    BinaryColorTheme, OutputSettingsBuilder, SimulatorDisplay, Window,
};

pub struct MyDisplay {
    window: Window,
    display: SimulatorDisplay<BinaryColor>,
}

impl Default for MyDisplay {
    fn default() -> Self {
        Self::new()
    }
}
impl MyDisplay {
    pub fn new() -> Self {
        let settings = OutputSettingsBuilder::new()
            .theme(BinaryColorTheme::OledBlue)
            .build();
        let window = Window::new("Digital clock", &settings);
        let display =
            SimulatorDisplay::<BinaryColor>::new(embedded_graphics::prelude::Size::new(250, 122));

        Self { window, display }
    }

    pub fn set_refresh(&mut self, mode: epd_waveshare::prelude::RefreshLut) {}

    pub const fn get_display<'a>(&'a mut self) -> NoopDisplay<'a, SimulatorDisplay<BinaryColor>> {
        NoopDisplay::new(&mut self.display)
    }

    pub fn update_and_display_frame(&mut self) {
        self.window.update(&mut self.display);
    }
}
