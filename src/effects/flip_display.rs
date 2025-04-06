use embedded_graphics::{
    Pixel,
    prelude::{DrawTarget, Point},
};

use super::filter_map_display::FilterMapDisplay;

pub fn make_flip_display<D: DrawTarget>(
    display: &'_ mut D,
) -> impl DrawTarget<Color = D::Color, Error = D::Error> {
    let w = display.bounding_box().size.width as i32;
    FilterMapDisplay::new(display, move |x| {
        Some(Pixel(
            Point {
                x: w - x.0.x,
                y: x.0.y,
            },
            x.1,
        ))
    })
}
