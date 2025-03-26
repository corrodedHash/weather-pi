use std::marker::PhantomData;

use embedded_graphics::{
    Pixel,
    pixelcolor::PixelColor,
    prelude::{Dimensions, DrawTarget},
    primitives::Rectangle,
};

pub struct FilterMapDisplay<
    'a,
    D: DrawTarget,
    C: PixelColor,
    F: FnMut(Pixel<C>) -> Option<Pixel<D::Color>>,
> {
    display: &'a mut D,
    mapping: F,
    _p: PhantomData<C>,
}

impl<'a, D: DrawTarget, C: PixelColor, F> FilterMapDisplay<'a, D, C, F>
where
    F: FnMut(Pixel<C>) -> Option<Pixel<D::Color>>,
{
    pub fn new(display: &'a mut D, mapping: F) -> Self {
        Self {
            display,
            mapping,
            _p: PhantomData::default(),
        }
    }
}

impl<D: DrawTarget, C: PixelColor, F> DrawTarget for FilterMapDisplay<'_, D, C, F>
where
    F: FnMut(Pixel<C>) -> Option<Pixel<D::Color>>,
{
    type Color = C;

    type Error = D::Error;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = embedded_graphics::Pixel<Self::Color>>,
    {
        self.display
            .draw_iter(pixels.into_iter().filter_map(|x| (self.mapping)(x)))
    }
}

impl<D: DrawTarget, C: PixelColor, F> Dimensions for FilterMapDisplay<'_, D, C, F>
where
    F: FnMut(Pixel<C>) -> Option<Pixel<D::Color>>,
{
    fn bounding_box(&self) -> Rectangle {
        self.display.bounding_box()
    }
}
