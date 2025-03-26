use std::{
    path::{Path, PathBuf}, sync::{atomic::AtomicBool, Arc}, thread::JoinHandle, time::Duration
};

use embedded_graphics::{
    draw_target::DrawTarget,
    geometry::OriginDimensions,
    pixelcolor::BinaryColor,
    prelude::{Dimensions, Point},
    primitives::Rectangle,
};
use epd_waveshare::color::Color;
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

pub fn building_image(
    v: &mut display::MyDisplay,
    keep_going: Option<&Arc<std::sync::atomic::AtomicBool>>,
    heart_bmp_path: &Path,
    max_fade: u32,
    min_fade: u32,
) {
    let heart_bmp_data = match std::fs::read(heart_bmp_path){
        Ok(data) => data,
        Err(e) => {
            eprintln!("Path: {}",heart_bmp_path.display());
            panic!("{e:#?}");
        },
    };
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

    v.set_refresh(epd_waveshare::prelude::RefreshLut::Quick);
    while black_pixel_count > 0 {
        if let Some(x) = keep_going {
            if !x.load(std::sync::atomic::Ordering::Relaxed) {
                return;
            }
        }
        let burst_size = ((black_pixel_count * max_fade) / (start_black_pixel_count))
            .max(min_fade);
        for _ in 0..(burst_size) {
            if black_pixel_count == 0 {
                break;
            }
            let bit_index = rand::rng()
                .random_range(0..black_pixel_count)
                .try_into()
                .unwrap();
            flip_nth_bit(false, bit_index, &mut mask);
            black_pixel_count = black_pixel_count.saturating_sub(1);
        }
        let mut new_data = heart.clone();

        overlay_binary(&mut new_data, &mask);

        let pixels = new_data
            .chunks(heart_bmp.size().width.div_ceil(8) as usize)
            .flat_map(|rows| {
                rows.iter()
                    .flat_map(|x| {
                        (0..8)
                            .rev()
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

fn watchdog(trigger: Arc<AtomicBool>, ip: &str) -> JoinHandle<()> {
    let ip = String::from(ip);
    std::thread::spawn(move || {
        let mut debounce_count = 0;
        let mut last_sent_event = None;
        loop {
            let a = std::process::Command::new("ping")
                .arg("-c1")
                .arg("-W0.2")
                .arg(&ip)
                .output()
                .expect("failed to execute process");
            let r = a.status.success();
            if let Some(l) = last_sent_event {
                if l != r {
                    debounce_count += 1;
                    if debounce_count > 5 {
                        debounce_count = 0;
                        trigger.store(r, std::sync::atomic::Ordering::Relaxed);
                        last_sent_event = Some(r);
                    }
                }
            } else {
                trigger.store(r, std::sync::atomic::Ordering::Relaxed);
                last_sent_event = Some(r);
            }
        }
    })
}

use config::Config;
#[derive(Debug, Default, serde_derive::Deserialize, PartialEq, Eq)]
struct GreeterConfig {
    watched_ip: String,
    heart_bmp_path: String,
    fade_max_velocity: u32,
    fade_min_velocity: u32,
}

pub fn greeter() {
    let config = Config::builder()
        .add_source(config::File::with_name("/etc/skyscreen/greeter"))
        .build()
        .unwrap();

    let app: GreeterConfig = config.try_deserialize().unwrap();
    dbg!(&app);
    let heart_bpm_path = PathBuf::from(app.heart_bmp_path);
    let kim_here = Arc::new(AtomicBool::new(false));
    let mut last_kim = false;

    let _w = watchdog(kim_here.clone(), &app.watched_ip);

    let mut v = display::MyDisplay::default();

    v.get_display().clear(Color::White).unwrap();
    v.update_and_display_frame();
    loop {
        if kim_here.load(std::sync::atomic::Ordering::Relaxed) == last_kim {
            std::thread::sleep(Duration::from_millis(500));
            continue;
        }

        last_kim = !last_kim;

        if last_kim {
            let font = u8g2_fonts::FontRenderer::new::<u8g2_fonts::fonts::u8g2_font_fub25_tr>();
            let text = "Hallo\nKim!";

            font.render_aligned(
                text,
                v.get_display().bounding_box().center() + Point::new(75, 0),
                u8g2_fonts::types::VerticalPosition::Center,
                u8g2_fonts::types::HorizontalAlignment::Center,
                u8g2_fonts::types::FontColor::Transparent(Color::Black),
                v.get_display(),
            )
            .unwrap();

            v.update_and_display_frame();
            building_image(
                &mut v,
                Some(&kim_here),
                &heart_bpm_path,
                app.fade_max_velocity,
                app.fade_min_velocity,
            );
        } else {
            v.get_display().clear(Color::White).unwrap();
            v.set_refresh(epd_waveshare::prelude::RefreshLut::Full);
            v.update_and_display_frame();
        }
    }
}
