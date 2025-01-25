use crate::delay::UnixDelay;
use embedded_graphics::{Drawable, prelude::Point};
use epd_waveshare::{color::Color, prelude::WaveshareDisplay};
use rppal::{
    gpio::{Gpio, InputPin, OutputPin},
    spi::{SimpleHalSpiDevice, Spi},
};

pub struct MyDisplay {
    bus: SimpleHalSpiDevice,
    epd: epd_waveshare::epd2in13_v2::Epd2in13<
        SimpleHalSpiDevice,
        InputPin,
        OutputPin,
        OutputPin,
        UnixDelay,
    >,
    display: epd_waveshare::epd2in13_v2::Display2in13,
}

impl Default for MyDisplay {
    fn default() -> Self {
        let gpio = Gpio::new().expect("Could not open GPIO");
        let busy_in = gpio.get(21).unwrap().into_input();
        let dc = gpio.get(16).unwrap().into_output_low();
        let rst = gpio.get(20).unwrap().into_output_low();

        Self::new(rppal::spi::Bus::Spi0, busy_in, dc, rst)
    }
}
impl MyDisplay {
    pub fn new(spi_bus: rppal::spi::Bus, busy_in: InputPin, dc: OutputPin, rst: OutputPin) -> Self {
        let spi = Spi::new(
            spi_bus,
            rppal::spi::SlaveSelect::Ss0,
            10_000_000,
            rppal::spi::Mode::Mode0,
        )
        .expect("Failed to initialize SPI");

        let mut spi_hal = rppal::spi::SimpleHalSpiDevice::new(spi);
        // Setup EPD
        let mut delay = UnixDelay {};
        let epd = epd_waveshare::epd2in13_v2::Epd2in13::new(
            &mut spi_hal,
            busy_in,
            dc,
            rst,
            &mut delay,
            None,
        )
        .unwrap();

        // Use display graphics from embedded-graphics
        let display = epd_waveshare::epd2in13_v2::Display2in13::default();
        Self {
            bus: spi_hal,
            epd,
            display,
        }
    }
    pub fn text(&mut self, text: &str, position: Point) {
        let mut delay = UnixDelay {};

        let style = embedded_graphics::mono_font::MonoTextStyle::new(
            &embedded_graphics::mono_font::ascii::FONT_6X10,
            Color::White,
        );

        // Create a text at position (20, 30) and draw it using the previously defined style
        embedded_graphics::text::Text::new(text, position, style)
            .draw(&mut self.display)
            .unwrap();

        self.epd
            .update_frame(&mut self.bus, self.display.buffer(), &mut delay)
            .unwrap();
        self.epd.display_frame(&mut self.bus, &mut delay).unwrap();

        // Set the EPD to sleep
        self.epd.sleep(&mut self.bus, &mut delay).unwrap();
    }
}
