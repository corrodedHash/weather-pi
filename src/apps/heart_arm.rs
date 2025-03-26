use std::{
    path::{Path, PathBuf},
    sync::{Arc, atomic::AtomicBool},
    thread::JoinHandle,
    time::Duration,
};

use embedded_graphics::{
    draw_target::DrawTarget,
    image::Image,
    pixelcolor::BinaryColor,
    prelude::{Dimensions, Drawable, Point},
};
use epd_waveshare::color::Color;

use crate::{
    display,
    effects::{color_map_display::ColorMapDisplay, hash_display::HashDisplay},
};

pub fn building_image(
    v: &mut display::MyDisplay,
    keep_going: Option<&Arc<std::sync::atomic::AtomicBool>>,
    heart_bmp_path: &Path,
    steps: u64,
) {
    let heart_bmp_data = match std::fs::read(heart_bmp_path) {
        Ok(data) => data,
        Err(e) => {
            eprintln!("Path: {}", heart_bmp_path.display());
            panic!("{e:#?}");
        }
    };
    let seed = rand::random::<u64>();
    let heart_bmp = tinybmp::Bmp::<'_, BinaryColor>::from_slice(&heart_bmp_data).unwrap();

    let heart_image = Image::new(&heart_bmp, Point::zero());

    let color_map = |x| match x {
        BinaryColor::On => Color::Black,
        BinaryColor::Off => Color::White,
    };
    v.set_refresh(epd_waveshare::prelude::RefreshLut::Quick);
    for i in 1u64..=steps {
        if let Some(k) = keep_going {
            if !k.load(std::sync::atomic::Ordering::Relaxed) {
                return;
            }
        }
        let mut d = HashDisplay::new(v.get_display(), seed, (u64::MAX / steps) * i);
        let mut c = ColorMapDisplay::new(&mut d, color_map);
        heart_image.draw(&mut c).unwrap();

        v.update_and_display_frame();
    }
    let mut c = ColorMapDisplay::new(v.get_display(), color_map);
    heart_image.draw(&mut c).unwrap();

    v.update_and_display_frame();
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
    steps: u64,
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
            building_image(&mut v, Some(&kim_here), &heart_bpm_path, app.steps);
        } else {
            v.get_display().clear(Color::White).unwrap();
            v.set_refresh(epd_waveshare::prelude::RefreshLut::Full);
            v.update_and_display_frame();
        }
    }
}
