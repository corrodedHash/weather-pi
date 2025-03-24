
struct OverlayImage{
    under: &dyn ImageDrawable<Color = <Self as ImageDrawable>::Color>,
    over: &dyn ImageDrawable
};

impl OriginDimensions for OverlayImage{
    fn size(&self) -> embedded_graphics::prelude::Size {
        self.under.size()
    }
}

impl ImageDrawable for OverlayImage{
    type Color = BinaryColor;

    fn draw<D>(&self, target: &mut D) -> Result<(), D::Error>
    where
        D: DrawTarget<Color = Self::Color> {
        self.draw_sub_image(target, &Rectangle::new(Point::zero(), self.size()))
    }

    fn draw_sub_image<D>(&self, target: &mut D, area: &Rectangle) -> Result<(), D::Error>
    where
        D: DrawTarget<Color = Self::Color> {

    }
}


