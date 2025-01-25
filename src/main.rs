use embedded_graphics::prelude::Point;

use std::io::BufRead;

mod delay;
mod display;
mod sensor;

fn main() {
    println!("hello");
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
    println!("Hello, world!");
}
