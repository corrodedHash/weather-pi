use crate::delay::UnixDelay;
use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    prelude::{Point, Size},
};
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
    refresh_count: u32,
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
            refresh_count: 0,
        }
    }

    pub fn text(&mut self, text: &str, position: Point) {
        let mut delay = UnixDelay {};

        if self.refresh_count > 10 {
            self.refresh_count = 0;
            self.epd
                .set_refresh(
                    &mut self.bus,
                    &mut delay,
                    epd_waveshare::prelude::RefreshLut::Full,
                )
                .unwrap();
        } else if self.refresh_count == 1 {
            self.epd
                .set_refresh(
                    &mut self.bus,
                    &mut delay,
                    epd_waveshare::prelude::RefreshLut::Quick,
                )
                .unwrap();
        }
        self.refresh_count += 1;
        let style = eg_seven_segment::SevenSegmentStyleBuilder::new()
            .digit_size(Size::new(20, 40))
            .digit_spacing(5)
            .segment_width(5)
            .segment_color(Color::Black)
            .build();
        self.display.clear(Color::White).unwrap();
        embedded_graphics::text::Text::new(text, position, style)
            .draw(&mut self.display)
            .unwrap();
        self.epd
            .update_and_display_frame(&mut self.bus, self.display.buffer(), &mut delay)
            .unwrap();
    }
}
