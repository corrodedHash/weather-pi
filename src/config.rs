use std::path::{Path, PathBuf};

use config::{Config, File};

/// Canonical configuration directory for this release.
pub const CANONICAL_DIR: &str = "/etc/weather-pi";
/// Directory used by releases before the rename. Read as a fallback for one
/// release; see the migration plan in the release-pipeline change.
pub const LEGACY_DIR: &str = "/etc/skyscreen";

/// Load `<name>.toml` from the canonical directory, falling back to the legacy
/// directory with a deprecation warning.
pub fn load(name: &str) -> Result<Config, config::ConfigError> {
    load_from(name, Path::new(CANONICAL_DIR), Path::new(LEGACY_DIR))
}

fn load_from(
    name: &str,
    canonical_dir: &Path,
    legacy_dir: &Path,
) -> Result<Config, config::ConfigError> {
    let path = source_path(name, canonical_dir, legacy_dir);

    Config::builder().add_source(File::from(path)).build()
}

fn source_path(name: &str, canonical_dir: &Path, legacy_dir: &Path) -> PathBuf {
    let canonical = canonical_dir.join(format!("{name}.toml"));
    if canonical.is_file() {
        return canonical;
    }

    let legacy = legacy_dir.join(format!("{name}.toml"));
    if legacy.is_file() {
        tracing::warn!(
            "Using deprecated configuration path {}; move it to {}",
            legacy.display(),
            canonical.display()
        );
        return legacy;
    }

    // Neither exists: return the canonical path so the resulting error names
    // the location operators are expected to create.
    canonical
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{load_from, source_path};

    struct TempTree {
        root: std::path::PathBuf,
    }

    impl TempTree {
        fn new() -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let root = std::env::temp_dir().join(format!(
                "weather-pi-config-test-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir_all(&root).unwrap();
            Self { root }
        }

        fn dir(&self, name: &str) -> std::path::PathBuf {
            let dir = self.root.join(name);
            fs::create_dir_all(&dir).unwrap();
            dir
        }
    }

    impl Drop for TempTree {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn canonical_path_wins_over_legacy() {
        let tree = TempTree::new();
        let canonical = tree.dir("etc-weather-pi");
        let legacy = tree.dir("etc-skyscreen");
        fs::write(canonical.join("greeter.toml"), "steps = 1").unwrap();
        fs::write(legacy.join("greeter.toml"), "steps = 2").unwrap();

        assert_eq!(
            source_path("greeter", &canonical, &legacy),
            canonical.join("greeter.toml")
        );
    }

    #[test]
    fn legacy_path_is_used_when_canonical_is_absent() {
        let tree = TempTree::new();
        let canonical = tree.dir("etc-weather-pi");
        let legacy = tree.dir("etc-skyscreen");
        fs::write(legacy.join("greeter.toml"), "steps = 2").unwrap();

        assert_eq!(
            source_path("greeter", &canonical, &legacy),
            legacy.join("greeter.toml")
        );
    }

    #[test]
    fn missing_configuration_errors_on_canonical_path() {
        let tree = TempTree::new();
        let canonical = tree.dir("etc-weather-pi");
        let legacy = tree.dir("etc-skyscreen");

        let error = load_from("greeter", &canonical, &legacy).unwrap_err();
        assert!(error.to_string().contains("etc-weather-pi"));
    }

    #[test]
    fn both_directories_load() {
        let tree = TempTree::new();
        let canonical = tree.dir("etc-weather-pi");
        let legacy = tree.dir("etc-skyscreen");
        fs::write(canonical.join("greeter.toml"), "steps = 1").unwrap();

        let empty_canonical = tree.dir("etc-weather-pi-empty");
        let legacy_only = tree.dir("etc-skyscreen-only");
        fs::write(legacy_only.join("greeter.toml"), "steps = 2").unwrap();

        let from_canonical = load_from("greeter", &canonical, &legacy).unwrap();
        let from_legacy = load_from("greeter", &empty_canonical, &legacy_only).unwrap();

        assert_eq!(from_canonical.get_int("steps").unwrap(), 1);
        assert_eq!(from_legacy.get_int("steps").unwrap(), 2);
    }
}
