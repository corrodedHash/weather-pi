use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    image::{Image, ImageRaw, ImageRawBE},
    pixelcolor::{BinaryColor, Rgb565},
    prelude::Point,
};
use embedded_graphics_simulator::{SimulatorDisplay, Window};

use std::{io::BufRead, time::Duration};

mod delay;
mod dht;
mod display;

#[allow(dead_code)]
fn text_loop() {
    let mut v = display::MyDisplay::default();

    let iterator = std::io::stdin().lock().lines();
    for (index, l) in iterator.enumerate() {
        let l = match l {
            Err(x) => {
                eprintln!("{x:#?}");
                return;
            }
            Ok(x) => x,
        };
        v.text(&l, Point::new(10, ((index % 10) * 10) as i32));
    }
}

#[allow(dead_code)]
fn temperature_display() {
    let mut v = display::MyDisplay::default();

    let mut error_count = 0;
    let print_point = Point::new(70, 60);
    loop {
        match dht::read(14) {
            Ok(x) => {
                error_count = 0;
                let text = format!("{}°C\n{}%", x.temperature, x.humidity);
                v.text(&text, print_point);
            }
            Err(x) => {
                eprintln!("{x:#?}");
                error_count += 1;
                if error_count == 10 {
                    v.text("Failing to read temperature often", print_point);
                }
            }
        }

        std::thread::sleep(Duration::from_secs(4));
    }
}

fn lazy_image_display() {
    let mut display =
        SimulatorDisplay::<BinaryColor>::new(embedded_graphics::prelude::Size::new(250, 122));

    let settings = embedded_graphics_simulator::OutputSettingsBuilder::new()
        .theme(embedded_graphics_simulator::BinaryColorTheme::OledBlue)
        .build();

    let mut window = Window::new("Digital clock", &settings);

    let x = std::fs::read("./assets/heart.bmp").unwrap();

    let bmp = tinybmp::Bmp::from_slice(&x).unwrap();
    // Create an `Image` object to position the image at `Point::zero()`.
    let image = Image::new(&bmp, Point::zero());

    // Draw the image to the display.
    display.clear(BinaryColor::Off).unwrap();
    image.draw(&mut display).unwrap();
    window.update(&mut display);
    std::thread::sleep(std::time::Duration::from_millis(10000));
}

fn main() {
    lazy_image_display();
}
