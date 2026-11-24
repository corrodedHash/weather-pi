#![warn(clippy::all, clippy::cargo, clippy::nursery, clippy::pedantic)]
// Don't know how to fix this, should be fine
#![allow(clippy::multiple_crate_versions)]
#![feature(iter_intersperse)]

mod apps;
mod config;
mod delay;
mod display;
mod effects;
// mod dht;
// mod overlay;

const VERSION: &str = env!("WEATHER_PI_VERSION");
const TARGET: &str = env!("WEATHER_PI_TARGET");

fn usage(program: &str) {
    eprintln!("Usage: {program} <command>");
    eprintln!("       {program} --version");
    eprintln!();
    eprintln!("Commands: greeter, countdown");
}

fn main() {
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::TRACE)
        .finish();

    if tracing::subscriber::set_global_default(subscriber).is_err() {
        eprintln!("Unable to set global default subscriber");
        return;
    }
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        usage(&args[0]);
        return;
    }

    match args[1].as_str() {
        "--version" | "-V" => println!("weather-pi {VERSION} ({TARGET})"),
        "greeter" => apps::greeter::greeter(),
        "countdown" => apps::countdown::countdown(),
        other => {
            eprintln!("Unknown command: {other}");
            usage(&args[0]);
        }
    }
}
