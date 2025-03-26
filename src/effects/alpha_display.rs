use embedded_graphics::{Pixel, prelude::DrawTarget};

use super::filter_map_display::FilterMapDisplay;

pub fn make_alpha_display<'a, D: DrawTarget>(
    display: &'a mut D,
    color_filter: D::Color,
) -> FilterMapDisplay<
    'a,
    D,
    <D as DrawTarget>::Color,
    impl FnMut(Pixel<<D as DrawTarget>::Color>) -> Option<Pixel<<D as DrawTarget>::Color>>,
> {
    FilterMapDisplay::new(
        display,
        move |x| if x.1 == color_filter { None } else { Some(x) },
    )
}
