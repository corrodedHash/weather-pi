use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    prelude::{Point, Size},
};
use epd_waveshare::{color::Color, prelude::WaveshareDisplay};

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

// TODO: This was a member function, just rewrite it to a standalone function, was cluttering. Sorry!

pub fn text(v: &mut display::MyDisplay, text: &str, position: Point, refresh_count: &mut u64) {
    let mut delay = UnixDelay {};

    if refresh_count > 10 {
        refresh_count = 0;
        self.set_refresh(epd_waveshare::prelude::RefreshLut::Full);
    } else if refresh_count == 1 {
        self.set_refresh(epd_waveshare::prelude::RefreshLut::Quick);
    }
    refresh_count += 1;
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
