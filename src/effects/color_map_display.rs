use embedded_graphics::{Pixel, pixelcolor::PixelColor, prelude::DrawTarget};

use super::filter_map_display::FilterMapDisplay;

pub fn make_color_map_display<D: DrawTarget, C: PixelColor>(
    display: &'_ mut D,
    mapping: fn(C) -> D::Color,
) -> impl DrawTarget<Color = C, Error = D::Error> {
    FilterMapDisplay::new(display, move |x| Some(Pixel(x.0, mapping(x.1))))
}
