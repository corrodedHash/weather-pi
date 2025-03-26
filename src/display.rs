use crate::delay::UnixDelay;
use epd_waveshare::prelude::WaveshareDisplay;
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
        let mut display = epd_waveshare::epd2in13_v2::Display2in13::default();
        display.set_rotation(epd_waveshare::prelude::DisplayRotation::Rotate270);
        Self {
            bus: spi_hal,
            epd,
            display,
        }
    }

    pub fn set_refresh(&mut self, mode: epd_waveshare::prelude::RefreshLut) {
        let mut delay = UnixDelay {};

        self.epd
            .set_refresh(&mut self.bus, &mut delay, mode)
            .unwrap();
    }

    pub const fn get_display(&mut self) -> &mut epd_waveshare::epd2in13_v2::Display2in13 {
        &mut self.display
    }

    pub fn update_and_display_frame(&mut self) {
        let mut delay = UnixDelay {};

        self.epd
            .update_and_display_frame(&mut self.bus, self.display.buffer(), &mut delay)
            .unwrap();
    }
}
