pub mod epd;

#[cfg(target_arch = "x86_64")]
pub mod sim;

#[cfg(target_arch = "arm")]
pub use epd::MyDisplay;

#[cfg(not(target_arch = "arm"))]
pub use sim::MyDisplay;
