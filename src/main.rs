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
    apps::heart_arm::greeter();
}
