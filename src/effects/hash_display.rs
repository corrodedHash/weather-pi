use std::hash::Hasher;

use embedded_graphics::prelude::{DrawTarget, Point};

use super::filter_map_display::FilterMapDisplay;

pub fn make_hash_display<D: DrawTarget>(
    display: &'_ mut D,
    seed: u64,
    target: u64,
) -> impl DrawTarget<Color = D::Color, Error = D::Error> {
    let good_pixel = move |x: Point| {
        let mut h = std::hash::DefaultHasher::new();
        h.write_u64(seed);
        h.write_i32(x.x);
        h.write_i32(x.y);
        let result = h.finish();
        result <= target
    };
    FilterMapDisplay::new(
        display,
        move |x| if good_pixel(x.0) { Some(x) } else { None },
    )
}
