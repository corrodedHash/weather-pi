use std::time::Duration;

use embedded_dht_rs::dht22::Dht22;

use rppal::gpio::Gpio;

struct IoPin {
    pin: rppal::gpio::IoPin,
}

impl embedded_hal::digital::ErrorType for IoPin {
    type Error = core::convert::Infallible;
}
impl embedded_hal::digital::InputPin for IoPin {
    fn is_high(&mut self) -> Result<bool, Self::Error> {
        self.pin.set_mode(rppal::gpio::Mode::Input);
        Ok(self.pin.is_high())
    }

    fn is_low(&mut self) -> Result<bool, Self::Error> {
        self.pin.set_mode(rppal::gpio::Mode::Input);
        Ok(self.pin.is_low())
    }
}

impl embedded_hal::digital::OutputPin for IoPin {
    fn set_low(&mut self) -> Result<(), Self::Error> {
        self.pin.set_mode(rppal::gpio::Mode::Output);
        self.pin.set_low();
        Ok(())
    }

    fn set_high(&mut self) -> Result<(), Self::Error> {
        self.pin.set_mode(rppal::gpio::Mode::Output);
        self.pin.set_high();
        Ok(())
    }
}
fn measure() {
    let mut dht = dht_mmap_rust::Dht::new(dht_mmap_rust::DhtType::Dht22, 14).unwrap();

    // Important: DHT sensor reads fail sometimes. In an actual program, if a read fails you should retry multiple times until
    // the read succeeds.
    // For more information, see documentation on `read()`
    let reading = dht.read().unwrap();

    println!(
        "Temperature {} °C, Humidity {}%RH",
        reading.temperature(),
        reading.humidity()
    );
}
