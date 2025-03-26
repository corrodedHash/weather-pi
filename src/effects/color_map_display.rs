use embedded_graphics::{
    Pixel,
    pixelcolor::PixelColor,
    prelude::{Dimensions, DrawTarget},
    primitives::Rectangle,
};

pub struct ColorMapDisplay<'a, D: DrawTarget, C: PixelColor> {
    display: &'a mut D,
    b: fn(C) -> D::Color,
}

impl<'a, D: DrawTarget, C: PixelColor> ColorMapDisplay<'a, D, C> {
    pub const fn new(display: &'a mut D, mapping: fn(C) -> D::Color) -> Self {
        Self {
            display,
            b: mapping,
        }
    }
}

impl<D: DrawTarget, C: PixelColor> DrawTarget for ColorMapDisplay<'_, D, C>
{
    type Color = C;

    type Error = D::Error;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = embedded_graphics::Pixel<Self::Color>>,
    {
        self.display
            .draw_iter(pixels.into_iter().map(|x| Pixel(x.0, (self.b)(x.1))))
    }
}

impl<D: DrawTarget, C: PixelColor> Dimensions for ColorMapDisplay<'_, D, C>
{
    fn bounding_box(&self) -> Rectangle {
        self.display.bounding_box()
    }
}
