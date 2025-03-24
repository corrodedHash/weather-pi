use embedded_graphics::{
    Drawable,
    draw_target::DrawTarget,
    geometry::OriginDimensions,
    image::{Image, ImageDrawable, ImageRawBE},
    pixelcolor::BinaryColor,
    prelude::Point,
    primitives::Rectangle,
};
use epd_waveshare::{color::Color, prelude::WaveshareDisplay};
use rand::Rng;

use crate::display;

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
    let mut v = display::MyDisplay::default();

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
        let mut new_data = heart.clone();

        overlay_binary(&mut new_data, &mask);
        // let image_raw = ImageRawBE::<BinaryColor>::new(&new_data, heart_bmp.size().width);
        // let image = Image::new(&image_raw, Point::zero());

        // image.draw( v.get_display()).unwrap();

        let pixels = new_data
            .chunks(heart_bmp.size().width.div_ceil(8) as usize)
            .flat_map(|rows| {
                rows.iter()
                    .flat_map(|x| {
                        (0..8)
                            .map(|b| {
                                if ((x >> b) & 1) == 1 {
                                    Color::White
                                } else {
                                    Color::Black
                                }
                            })
                            .collect::<Vec<_>>()
                    })
                    .take(heart_bmp.size().width as usize)
                    .collect::<Vec<_>>()
            });
        v.get_display()
            .fill_contiguous(&Rectangle::new(Point::zero(), heart_bmp.size()), pixels)
            .unwrap();

        v.update_and_display_frame();
    }
}
