use std::process::Command;

fn ip_in_network(ip: &str) -> bool {
    let a = Command::new("ping")
        .arg("-c1")
        .arg("-W0.2")
        .arg(ip)
        .output()
        .expect("failed to execute process");
    a.status.success()
}

pub fn greeter() {
    let mut kim_here = false;
    let kim_ip = "192.168.178.28";
    loop {
        
        if ip_in_network(kim_ip) {
            dbg!("Found you!");
        } else {
            dbg!("Marco!");
        }
        std::thread::sleep(std::time::Duration::from_millis(400));
    }
}
