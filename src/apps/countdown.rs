use std::time::Duration;

use embedded_graphics::{
    pixelcolor::BinaryColor,
    prelude::{Dimensions, DrawTarget},
};

use crate::display;

pub fn countdown() {
    let mut v = display::MyDisplay::default();

    v.get_display().clear(BinaryColor::Off).unwrap();
    v.update_and_display_frame();

    let font = u8g2_fonts::FontRenderer::new::<u8g2_fonts::fonts::u8g2_font_fub25_tr>();
    let target = chrono::NaiveDate::from_ymd_opt(2025, 4, 14)
        .unwrap()
        .and_hms_opt(19, 00, 00)
        .unwrap()
        .and_local_timezone(chrono::Local)
        .unwrap();
    let n = chrono::Local::now();
    let q = target - n;
    let text = format!(
        "{} Tage\n{} Stunden\n{} Minuten",
        q.num_days(),
        q.num_hours() - q.num_days() * 24,
        q.num_minutes() - q.num_hours() * 60,
    );

    font.render_aligned(
        text.as_str(),
        v.get_display().bounding_box().center(),
        u8g2_fonts::types::VerticalPosition::Center,
        u8g2_fonts::types::HorizontalAlignment::Center,
        u8g2_fonts::types::FontColor::Transparent(BinaryColor::On),
        &mut v.get_display(),
    )
    .unwrap();

    v.update_and_display_frame();
    std::thread::sleep(Duration::from_secs(5));
}
