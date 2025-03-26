#![warn(
    clippy::all,
    clippy::pedantic,
    clippy::nursery,
    clippy::cargo,
)]

// Don't know how to fix this, should be fine
#![allow(clippy::multiple_crate_versions)]

mod apps;
mod delay;
// mod dht;
mod display;

fn main() {
    apps::heart_arm::greeter();
}
