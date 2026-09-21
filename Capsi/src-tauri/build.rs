// Capsi - Tauri build script.
//
// `tauri-build` does two jobs on Windows: it turns `tauri.conf.json` into the
// constants, ACL data and `cfg` aliases that `tauri::generate_context!` needs,
// and it embeds the app icon, manifest and version metadata into the executable.
//
// The embed step shells out to an external resource compiler - `windres` for a
// `*-pc-windows-gnu` target, `rc.exe` from the Windows SDK for a
// `*-pc-windows-msvc` target - and `tauri-build` treats its absence as fatal.
// A machine with neither cannot build *any* Tauri app, which makes that failure
// hard to tell apart from a real problem in Capsi's own code.
//
// Everything valuable happens *before* the embed step, which runs last. So when
// no resource compiler is on `PATH` we let the build run and swallow only that
// final failure, warning instead of aborting. A machine that is provisioned
// properly is completely unaffected, and `cargo check` / `cargo build` stay
// usable here. Install the "Desktop development with C++" workload (Visual
// Studio Build Tools) for `rc.exe`, or mingw-w64 for `windres`, to get the
// icon, manifest and version metadata embedded.

use std::env;
use std::path::PathBuf;

fn main() {
    if resource_compiler().is_some() {
        tauri_build::build();
        return;
    }

    // Silence the panic that `tauri-build` raises over the missing tool; the
    // warning below says the same thing without looking like a crash.
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let embedded = std::panic::catch_unwind(tauri_build::build).is_ok();
    std::panic::set_hook(previous_hook);

    if !embedded {
        println!(
            "cargo:warning=Capsi: no Windows resource compiler found (expected `windres` \
             on a GNU target or `rc.exe` on an MSVC target), so the icon, manifest and \
             version metadata were not embedded. Install the C++ build tools or mingw-w64 \
             and rebuild for a fully badged executable."
        );
    }
}

/// The resource compiler `tauri-build` will reach for, if it is on `PATH`.
///
/// `embed-resource` honours `RC`, `RC_<target-triple>` and `RC_<target_triple>`
/// before falling back to the platform default, so those are checked first and
/// an unusual toolchain can point at its own copy.
fn resource_compiler() -> Option<PathBuf> {
    let target = env::var("TARGET").unwrap_or_default();
    let mut candidates = Vec::new();

    for key in [
        format!("RC_{target}"),
        format!("RC_{}", target.replace('-', "_")),
        "RC".to_string(),
    ] {
        if let Some(value) = env::var_os(&key) {
            candidates.push(value.to_string_lossy().into_owned());
        }
    }

    if target.contains("gnu") {
        candidates.push("windres".to_string());
        if let Some(arch) = target.split('-').next() {
            candidates.push(format!("{arch}-w64-mingw32-windres"));
        }
    } else {
        candidates.push("rc.exe".to_string());
        candidates.push("llvm-rc".to_string());
    }

    candidates.iter().find_map(|name| find_on_path(name))
}

/// Resolve `name` the way a shell would: a real path is used as-is, otherwise
/// every `PATH` entry is tried, with and without `.exe`.
fn find_on_path(name: &str) -> Option<PathBuf> {
    let direct = PathBuf::from(name);
    if direct.is_file() {
        return Some(direct);
    }
    for dir in env::split_paths(&env::var_os("PATH").unwrap_or_default()) {
        for suffix in [".exe", ""] {
            let candidate = dir.join(format!("{name}{suffix}"));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}
