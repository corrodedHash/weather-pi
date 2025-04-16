#![warn(clippy::all, clippy::cargo, clippy::nursery, clippy::pedantic)]
// Don't know how to fix this, should be fine
#![allow(clippy::multiple_crate_versions)]

mod apps;
mod delay;
mod display;
mod effects;
// mod dht;
// mod overlay;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: {} <command>", args[0]);
        return;
    }

    match args[1].as_str() {
        "greeter" => apps::greeter::greeter(),
        "countdown" => apps::countdown::countdown(),
        _ => eprintln!("Unknown command: {}", args[1]),
    }
}
