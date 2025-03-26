use embedded_graphics::{
    prelude::{Dimensions, DrawTarget},
    primitives::Rectangle,
};

pub struct NoopDisplay<'a, D: DrawTarget> {
    display: &'a mut D,
}

impl<'a, D: DrawTarget> NoopDisplay<'a, D> {
    pub const fn new(display: &'a mut D) -> Self {
        Self { display }
    }
}

impl<D: DrawTarget> DrawTarget for NoopDisplay<'_, D> {
    type Color = D::Color;

    type Error = D::Error;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = embedded_graphics::Pixel<Self::Color>>,
    {
        self.display.draw_iter(pixels)
    }
}

impl<D: DrawTarget> Dimensions for NoopDisplay<'_, D> {
    fn bounding_box(&self) -> Rectangle {
        self.display.bounding_box()
    }
}
