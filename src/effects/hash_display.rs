use std::hash::Hasher;

use embedded_graphics::{
    prelude::{Dimensions, DrawTarget, Point},
    primitives::Rectangle,
};

pub struct HashDisplay<'a, C: DrawTarget> {
    seed: u64,
    target: u64,
    display: &'a mut C,
}

impl<'a, C: DrawTarget> HashDisplay<'a, C> {
    pub const fn new(display: &'a mut C, seed: u64, target: u64) -> Self {
        Self {
            seed,
            target,
            display,
        }
    }
}

impl<C> DrawTarget for HashDisplay<'_, C>
where
    C: DrawTarget,
{
    type Color = C::Color;

    type Error = C::Error;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = embedded_graphics::Pixel<Self::Color>>,
    {
        let good_pixel = |x: Point| {
            let mut h = std::hash::DefaultHasher::new();
            h.write_u64(self.seed);
            h.write_i32(x.x);
            h.write_i32(x.y);
            let result = h.finish();
            result <= self.target
        };
        self.display
            .draw_iter(pixels.into_iter().filter(|x| good_pixel(x.0)))
    }
}

impl<C> Dimensions for HashDisplay<'_, C>
where
    C: DrawTarget,
{
    fn bounding_box(&self) -> Rectangle {
        self.display.bounding_box()
    }
}
