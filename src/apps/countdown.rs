use std::{path::Path, time::Duration};

use chrono::TimeDelta;
use embedded_graphics::{
    image::Image,
    pixelcolor::BinaryColor,
    prelude::{Dimensions, DrawTarget, Drawable, Point},
};

use crate::{
    display::{self, MyDisplay},
    effects::flip_display::make_flip_display,
};

fn draw_time(v: &mut MyDisplay, q: TimeDelta) {
    let font = u8g2_fonts::FontRenderer::new::<u8g2_fonts::fonts::u8g2_font_fub17_tr>();
    let text = if q.num_days() > 0 {
        format!(
            "{} Tage\n{} Stunden\n{} Minuten",
            q.num_days(),
            q.num_hours() - q.num_days() * 24,
            q.num_minutes() - q.num_hours() * 60,
        )
    } else {
        format!(
            "{} Stunden\n{} Minuten",
            q.num_hours(),
            q.num_minutes() - q.num_hours() * 60,
        )
    };

    let text_position = v.get_display().bounding_box().center();
    v.get_display().clear(BinaryColor::Off).unwrap();
    font.render_aligned(
        text.as_str(),
        text_position,
        u8g2_fonts::types::VerticalPosition::Center,
        u8g2_fonts::types::HorizontalAlignment::Center,
        u8g2_fonts::types::FontColor::Transparent(BinaryColor::On),
        &mut v.get_display(),
    )
    .unwrap();
    v.update_and_display_frame();
}

fn dickbutt(v: &mut MyDisplay, dickbutt_path: &Path) {
    v.get_display().clear(BinaryColor::On).unwrap();
    let dickbutt_bmp_data = match std::fs::read(dickbutt_path) {
        Ok(data) => data,
        Err(e) => {
            tracing::error!("Path: {}", dickbutt_path.display());
            panic!("{e:#?}");
        }
    };
    let heart_bmp = tinybmp::Bmp::<'_, BinaryColor>::from_slice(&dickbutt_bmp_data).unwrap();

    let heart_image = Image::new(&heart_bmp, Point::zero());

    heart_image.draw(&mut v.get_display()).unwrap();
    {
        heart_image
            .draw(&mut make_flip_display(&mut v.get_display()))
            .unwrap();
    }
    v.update_and_display_frame();
}

use config::Config;
#[derive(Debug, Default, serde_derive::Deserialize, PartialEq, Eq)]
struct CountdownConfig {
    dickbutt_path: String,
    target_time: String,
}
pub fn countdown() {
    let app: CountdownConfig = if cfg!(target_arch = "x86_64") {
        CountdownConfig {
            dickbutt_path: "./assets/dickbutt.bmp".to_owned(),
            target_time: "2025-04-14T19:00:00+02:00".to_owned(),
        }
    } else {
        let config = Config::builder()
            .add_source(config::File::with_name("/etc/skyscreen/countdown"))
            .build()
            .unwrap();

        config.try_deserialize().unwrap()
    };
    let target = chrono::DateTime::parse_from_rfc3339(&app.target_time).unwrap();

    let mut v = display::MyDisplay::default();
    v.set_refresh(epd_waveshare::prelude::RefreshLut::Full);

    loop {
        let n = chrono::Local::now().fixed_offset();
        let q = target - n;
        if q.num_seconds() > 0 {
            draw_time(&mut v, q);
        } else {
            dickbutt(&mut v, Path::new(&app.dickbutt_path));
        }

        std::thread::sleep(Duration::from_secs(60));
    }
}
