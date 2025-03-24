use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    geometry::OriginDimensions,
    image::{Image, ImageRawBE, ImageRawLE},
    mono_font::{MonoTextStyle, ascii},
    pixelcolor::BinaryColor,
    prelude::Point,
    primitives::Rectangle,
};
use embedded_graphics_simulator::{SimulatorDisplay, Window};
use embedded_text::{
    TextBox,
    alignment::HorizontalAlignment,
    style::{HeightMode, TextBoxStyleBuilder},
};
use rand::Rng;

fn lazy_image_display() {
    let mut display =
        SimulatorDisplay::<BinaryColor>::new(embedded_graphics::prelude::Size::new(250, 122));

    let settings = embedded_graphics_simulator::OutputSettingsBuilder::new()
        .theme(embedded_graphics_simulator::BinaryColorTheme::OledBlue)
        .build();

    let mut window = Window::new("Digital clock", &settings);

    let x = std::fs::read("./assets/heart.bmp").unwrap();

    let bmp = tinybmp::Bmp::from_slice(&x).unwrap();

    // Create an `Image` object to position the image at `Point::zero()`.
    let image = Image::new(&bmp, Point::zero());

    // Draw the image to the display.
    display.clear(BinaryColor::Off).unwrap();
    image.draw(&mut display).unwrap();
    window.update(&display);
    std::thread::sleep(std::time::Duration::from_millis(10000));
}

fn scrolling_text() {
    let mut display =
        SimulatorDisplay::<BinaryColor>::new(embedded_graphics::prelude::Size::new(250, 122));

    let settings = embedded_graphics_simulator::OutputSettingsBuilder::new()
        .theme(embedded_graphics_simulator::BinaryColorTheme::OledBlue)
        .build();

    let mut window = Window::new("Digital clock", &settings);
    let text = "Cutie detected...\nClearing caches...\nRunning diagnostics...";

    let character_style = MonoTextStyle::new(&ascii::FONT_5X8, BinaryColor::On);
    let textbox_style = TextBoxStyleBuilder::new()
        .height_mode(HeightMode::FitToText)
        .alignment(HorizontalAlignment::Justified)
        .paragraph_spacing(6)
        .build();

    // Specify the bounding box. Note the 0px height. The `FitToText` height mode will
    // measure and adjust the height of the text box in `into_styled()`.
    let bounds = Rectangle::new(
        Point::new(125, 0),
        embedded_graphics::prelude::Size::new(125, 0),
    );

    // Create the text box and apply styling options.
    let mut text_box = TextBox::with_textbox_style("", bounds, character_style, textbox_style);
    for i in 1..=text.len() {
        text_box.text = &text[0..i];
        dbg!("text");
        text_box.draw(&mut display).unwrap();
        dbg!("window");

        window.update(&display);
    }
    window.show_static(&display);
    // Draw the text box.
}
