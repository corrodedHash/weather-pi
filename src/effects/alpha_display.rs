use embedded_graphics::prelude::DrawTarget;

use super::filter_map_display::FilterMapDisplay;

pub fn make_alpha_display<D: DrawTarget>(
    display: &'_ mut D,
    color_filter: D::Color,
) -> impl DrawTarget<Color = D::Color, Error = D::Error> {
    FilterMapDisplay::new(
        display,
        move |x| if x.1 == color_filter { None } else { Some(x) },
    )
}
