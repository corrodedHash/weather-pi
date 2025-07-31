use std::{
    net::Ipv4Addr,
    path::{Path, PathBuf},
    process::Child,
    thread::JoinHandle,
    time::Duration,
};

use embedded_graphics::{
    draw_target::DrawTarget,
    image::Image,
    pixelcolor::BinaryColor,
    prelude::{Dimensions, Drawable, Point},
};

use crate::{
    display,
    effects::{alpha_display::make_alpha_display, hash_display::make_hash_display},
};

pub fn building_image(v: &mut display::MyDisplay, heart_bmp_path: &Path, steps: u64) {
    let heart_bmp_data = match std::fs::read(heart_bmp_path) {
        Ok(data) => data,
        Err(e) => {
            tracing::error!("Path: {}", heart_bmp_path.display());
            panic!("{e:#?}");
        }
    };
    let seed = rand::random::<u64>();
    let heart_bmp = tinybmp::Bmp::<'_, BinaryColor>::from_slice(&heart_bmp_data).unwrap();

    let heart_image = Image::new(&heart_bmp, Point::zero());

    v.set_refresh(epd_waveshare::prelude::RefreshLut::Quick);
    for i in 1u64..=steps {
        {
            let mut c = v.get_display();
            let mut f = make_alpha_display(&mut c, BinaryColor::Off);
            let mut d = make_hash_display(&mut f, seed, (u64::MAX / steps) * i);
            heart_image.draw(&mut d).unwrap();
        }

        v.update_and_display_frame();
    }
    {
        let mut c = v.get_display();
        let mut f = make_alpha_display(&mut c, BinaryColor::Off);
        heart_image.draw(&mut f).unwrap();
    }

    v.update_and_display_frame();
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum NetworkEventType {
    Connected,
    Left,
}
#[derive(Debug, Clone)]
struct NetworkEvent {
    ip: std::net::Ipv4Addr,
    ev: NetworkEventType,
}

fn watchdog(
    channel: std::sync::mpsc::SyncSender<NetworkEvent>,
    ips: &[std::net::Ipv4Addr],
) -> JoinHandle<()> {
    let mut ping_commands = ips
        .iter()
        .map(|x| {
            let mut c = std::process::Command::new("ping");
            c.arg("-c1")
                .arg("-W0.2")
                .arg(x.to_string())
                .stdout(std::process::Stdio::piped());
            c
        })
        .collect::<Vec<_>>();
    let mut last_sent_events: Vec<Option<bool>> = ips.iter().map(|_| None).collect::<Vec<_>>();
    let mut debounces = ips.iter().map(|_| 0u8).collect::<Vec<_>>();
    let ips = ips.to_vec();
    std::thread::spawn(move || {
        loop {
            let mut v = match ping_commands
                .iter_mut()
                .map(std::process::Command::spawn)
                .collect::<std::io::Result<Vec<Child>>>()
            {
                Ok(r) => r,
                Err(e) => {
                    tracing::error!("Could not start ping command: {e}");
                    tracing::error!("Sleeping for 120 seconds");
                    std::thread::sleep(Duration::from_secs(120));
                    continue;
                }
            };

            let mut wait_count = 0;
            while v
                .iter_mut()
                .any(|c| c.try_wait().is_ok_and(|v| v.is_none()))
            {
                if wait_count > 0 {
                    tracing::info!("Waiting for pings #{wait_count}");
                }
                wait_count += 1;
                std::thread::sleep(Duration::from_millis(300));
            }
            for (index, mut c) in v.into_iter().enumerate() {
                let last_sent_event = last_sent_events.get_mut(index).unwrap();
                let debounce_count = debounces.get_mut(index).unwrap();
                let result = match c.wait() {
                    Ok(e) => e,
                    Err(err) => {
                        tracing::error!("Error running ping command to {}: {err}", ips[index]);
                        return;
                    }
                };
                let r = result.success();
                let send_event: bool = last_sent_event.is_none_or(|l| {
                    if l == r {
                        *debounce_count = 0;
                        false
                    } else {
                        *debounce_count += 1;
                        if *debounce_count > 5 {
                            *debounce_count = 0;
                            true
                        } else {
                            false
                        }
                    }
                });
                if send_event {
                    let event = NetworkEvent {
                        ip: *ips.get(index).unwrap(),
                        ev: if r {
                            NetworkEventType::Connected
                        } else {
                            NetworkEventType::Left
                        },
                    };
                    tracing::debug!("{:#?}", event);
                    if channel.send(event).is_err() {
                        tracing::error!("Channel closed, thread returning");
                        return;
                    }
                    *last_sent_event = Some(r);
                }
            }
        }
    })
}

use config::Config;
#[derive(Debug, Default, serde_derive::Deserialize, PartialEq, Eq)]
struct GreeterConfig {
    watched_ips: Vec<Ipv4Addr>,
    heart_bmp_path: String,
    steps: u64,
}

pub fn greeter() {
    let app: GreeterConfig = if cfg!(target_arch = "x86_64") {
        GreeterConfig {
            watched_ips: vec!["192.168.178.29".parse().unwrap()],
            heart_bmp_path: "./assets/heart_full.bmp".to_owned(),
            steps: 10,
        }
    } else {
        let config = Config::builder()
            .add_source(config::File::with_name("/etc/skyscreen/greeter"))
            .build()
            .unwrap();

        config.try_deserialize().unwrap()
    };
    tracing::info!("{:#?}", &app);
    let heart_bpm_path = PathBuf::from(app.heart_bmp_path);

    let (chan_in, chan_out) = std::sync::mpsc::sync_channel(20);

    let _w = watchdog(chan_in, &app.watched_ips);

    let mut v = display::MyDisplay::default();

    v.get_display().clear(BinaryColor::Off).unwrap();
    v.update_and_display_frame();
    let mut connected_ips = vec![];
    loop {
        let mut changes_made = false;

        if let Ok(x) = chan_out.recv() {
            changes_made |= handle_event(&mut connected_ips, &x);
        } else {
            tracing::error!("Channel closed, program exiting");
            return;
        }

        // Siphon out simultaneous network events
        loop {
            match chan_out.recv_timeout(Duration::from_secs_f64(0.3)) {
                Ok(x) => {
                    changes_made |= handle_event(&mut connected_ips, &x);
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => break,
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                    tracing::error!("Channel closed, program exiting");
                    return;
                }
            }
        }
        if !changes_made {
            continue;
        }

        if connected_ips.is_empty() {
            v.get_display().clear(BinaryColor::Off).unwrap();
            v.set_refresh(epd_waveshare::prelude::RefreshLut::Full);
            v.update_and_display_frame();
        } else {
            if connected_ips.len() != 1 {
                continue;
            }
            let font = u8g2_fonts::FontRenderer::new::<u8g2_fonts::fonts::u8g2_font_fub25_tr>();
            let text = "Hallo\nKim!";
            let text_position = v.get_display().bounding_box().center();

            v.get_display().clear(BinaryColor::Off).unwrap();
            v.set_refresh(epd_waveshare::prelude::RefreshLut::Full);
            v.update_and_display_frame();

            font.render_aligned(
                text,
                text_position,
                u8g2_fonts::types::VerticalPosition::Center,
                u8g2_fonts::types::HorizontalAlignment::Center,
                u8g2_fonts::types::FontColor::Transparent(BinaryColor::On),
                &mut v.get_display(),
            )
            .unwrap();

            // let tiny_font =
            //     u8g2_fonts::FontRenderer::new::<u8g2_fonts::fonts::u8g2_font_fub11_tr>();
            // let ip_position = v.get_display().bounding_box().bottom_right().unwrap();
            // tiny_font
            //     .render_aligned(
            //         connected_ips
            //             .iter()
            //             .map(std::string::ToString::to_string)
            //             .intersperse("\n".to_owned())
            //             .collect::<String>()
            //             .as_str(),
            //         ip_position,
            //         u8g2_fonts::types::VerticalPosition::Bottom,
            //         u8g2_fonts::types::HorizontalAlignment::Right,
            //         u8g2_fonts::types::FontColor::Transparent(BinaryColor::On),
            //         &mut v.get_display(),
            //     )
            //     .unwrap();

            v.update_and_display_frame();
            building_image(&mut v, &heart_bpm_path, app.steps);
        }
    }
}

fn handle_event(connected_ips: &mut Vec<Ipv4Addr>, x: &NetworkEvent) -> bool {
    match x.ev {
        NetworkEventType::Connected => {
            if connected_ips.contains(&x.ip) {
                tracing::warn!("IP {} entered twice", x.ip);
                return false;
            }
            connected_ips.push(x.ip);
            true
        }
        NetworkEventType::Left => {
            if connected_ips.contains(&x.ip) {
                connected_ips.retain(|v| v != &x.ip);
                return true;
            }
            false
        }
    }
}
