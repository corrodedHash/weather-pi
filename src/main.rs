use embedded_graphics::prelude::Point;

use std::{io::BufRead, time::Duration};

mod delay;
mod display;
mod dht;

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

fn main() {
    println!("Hello World!");

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
