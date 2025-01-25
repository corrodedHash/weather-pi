use std::time::Duration;


pub struct UnixDelay;

impl embedded_hal::delay::DelayNs for UnixDelay {
    fn delay_ns(&mut self, ns: u32) {
        std::thread::sleep(Duration::from_nanos(ns.into()));
    }
}
