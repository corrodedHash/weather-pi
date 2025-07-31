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

    #[allow(
        unused_variables,
        clippy::unused_self,
        clippy::needless_pass_by_ref_mut
    )]
    pub const fn set_refresh(&mut self, mode: epd_waveshare::prelude::RefreshLut) {}

    pub const fn get_display(&'_ mut self) -> NoopDisplay<'_, SimulatorDisplay<BinaryColor>> {
        NoopDisplay::new(&mut self.display)
    }

    pub fn update_and_display_frame(&mut self) {
        self.window.update(&self.display);
        // if self
        //     .window
        //     .events()
        //     .inspect(|x| {
        //         dbg!(x);
        //     })
        //     .any(|event| event == embedded_graphics_simulator::SimulatorEvent::Quit)
        // {
        //     panic!("Exit please");
        // }
    }
}
