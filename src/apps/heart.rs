use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    geometry::OriginDimensions,
    image::{Image, ImageRawBE},
    pixelcolor::BinaryColor,
    prelude::Point,
};
use embedded_graphics_simulator::{SimulatorDisplay, Window};
use rand::Rng;

fn flip_nth_bit(toggle_one: bool, n: usize, array: &mut [u8]) {
    let mut count = 0;
    for c in array.iter_mut() {
        for b in 0..8 {
            if (((*c >> b) & 1) == 1) == toggle_one {
                if count == n {
                    if toggle_one {
                        *c &= !(1u8 << b);
                    } else {
                        *c |= 1u8 << b;
                    }
                    return;
                }
                count += 1;
            }
        }
    }
}

/// If `over` is 1, it is transparent. Otherwise, `under` will always turn into a 1
fn overlay_binary(under: &mut [u8], over: &[u8]) {
    under.iter_mut().zip(over).for_each(|(u, o)| *u |= !o);
}

pub fn building_image() {
    let mut display =
        SimulatorDisplay::<BinaryColor>::new(embedded_graphics::prelude::Size::new(250, 122));

    let settings = embedded_graphics_simulator::OutputSettingsBuilder::new()
        .theme(embedded_graphics_simulator::BinaryColorTheme::OledBlue)
        .build();

    let mut window = Window::new("Digital clock", &settings);

    let heart_bmp_data = std::fs::read("./assets/heart.bmp").unwrap();
    let heart_bmp = tinybmp::Bmp::<'_, BinaryColor>::from_slice(&heart_bmp_data).unwrap();

    let heart = heart_bmp
        .pixels()
        .map(|x| x.1)
        .collect::<Vec<_>>()
        .chunks(heart_bmp.size().width as usize)
        .flat_map(|x| {
            x.chunks(8)
                .map(|x| {
                    let mut r = 0u8;
                    for b in x {
                        r <<= 1;
                        if b.is_on() {
                            r |= 1;
                        }
                    }
                    r <<= 8 - x.len();
                    r
                })
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();

    let mut mask = heart.clone();
    let mut black_pixel_count = mask.iter().fold(0, |x, y| x + y.count_zeros());
    let start_black_pixel_count = black_pixel_count;
    display.clear(BinaryColor::On).unwrap();

    loop {
        let burst_size = ((black_pixel_count * 10) / (start_black_pixel_count)).max(1);
        for _ in 0..(burst_size) {
            let bit_index = rand::rng()
                .random_range(0..black_pixel_count)
                .try_into()
                .unwrap();
            flip_nth_bit(false, bit_index, &mut mask);
            black_pixel_count = black_pixel_count.saturating_sub(1);
        }
        dbg!(mask.iter().fold(0, |x, y| x + y.count_zeros()));
        dbg!(black_pixel_count);
        let mut new_data = heart.clone();

        overlay_binary(&mut new_data, &mask);
        let image_raw = ImageRawBE::<BinaryColor>::new(&new_data, heart_bmp.size().width);
        let image = Image::new(&image_raw, Point::zero());

        image.draw(&mut display).unwrap();
        window.update(&display);
    }
}
