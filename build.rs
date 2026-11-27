use std::{env, path::Path, process::Command};

/// Compile-time version stamp.
///
/// Resolution order:
/// 1. `WEATHER_PI_VERSION` (set by the release workflow and the package build).
/// 2. `git describe --tags --always --dirty` so a local build identifies its
///    exact revision.
/// 3. The crate version from `Cargo.toml`, which keeps non-git source archives
///    buildable.
fn version() -> String {
    if let Ok(v) = env::var("WEATHER_PI_VERSION") {
        let v = v.trim().to_owned();
        if !v.is_empty() {
            return v;
        }
    }

    if let Some(v) = git_describe() {
        return v;
    }

    env::var("CARGO_PKG_VERSION").unwrap_or_else(|_| "0.0.0".to_owned())
}

fn git_describe() -> Option<String> {
    let output = Command::new("git")
        .args(["describe", "--tags", "--always", "--dirty"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let describe = String::from_utf8(output.stdout).ok()?;
    let describe = describe.trim();

    if describe.is_empty() {
        None
    } else {
        Some(describe.to_owned())
    }
}

fn main() {
    println!("cargo:rerun-if-env-changed=WEATHER_PI_VERSION");
    println!("cargo:rerun-if-changed=.git/HEAD");

    if let Ok(head) = Path::new(".git/HEAD").canonicalize() {
        println!("cargo:rerun-if-changed={}", head.display());
    }

    let target = env::var("TARGET").unwrap_or_else(|_| "unknown".to_owned());

    println!("cargo:rustc-env=WEATHER_PI_VERSION={}", version());
    println!("cargo:rustc-env=WEATHER_PI_TARGET={target}");
}
