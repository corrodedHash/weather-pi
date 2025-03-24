use embedded_graphics::
    prelude::Point
;
use embedded_graphics_simulator::{SimulatorDisplay, Window};
use embedded_text::{
    TextBox,
    alignment::HorizontalAlignment,
    style::{HeightMode, TextBoxStyleBuilder},
};

use std::{io::BufRead, time::Duration};

mod delay;
mod dht;
mod display;
mod apps;


fn main() {
    apps::heart_arm::building_image();
}
