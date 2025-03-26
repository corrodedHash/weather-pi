use embedded_graphics::{
    image::ImageDrawable,
    pixelcolor::BinaryColor,
    prelude::{DrawTarget, OriginDimensions, Point},
    primitives::Rectangle,
};

struct OverlayImage<'a, 'b, U, O>
where
    U: ImageDrawable<Color = BinaryColor>,
    O: ImageDrawable<Color = BinaryColor>,
{
    under: &'a U,
    over: &'b O,
}

impl<U, O> OriginDimensions for OverlayImage<'_, '_, U, O>
where
    U: ImageDrawable<Color = BinaryColor>,
    O: ImageDrawable<Color = BinaryColor>,
{
    fn size(&self) -> embedded_graphics::prelude::Size {
        self.under.size()
    }
}

impl<U, O> ImageDrawable for OverlayImage<'_, '_, U, O>
where
    U: ImageDrawable<Color = BinaryColor>,
    O: ImageDrawable<Color = BinaryColor>,
{
    type Color = BinaryColor;

    fn draw<D>(&self, target: &mut D) -> Result<(), D::Error>
    where
        D: DrawTarget<Color = Self::Color>,
    {
        self.draw_sub_image(target, &Rectangle::new(Point::zero(), self.size()))
    }

    fn draw_sub_image<D>(&self, target: &mut D, area: &Rectangle) -> Result<(), D::Error>
    where
        D: DrawTarget<Color = Self::Color>,
    {
        todo!()
    }
}
