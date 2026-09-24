// Capsi by CAPSICOM - "Download. Run. Connect."
//
// Thin binary wrapper: all wiring lives in `capsi_lib::run()` so desktop and
// mobile (via `tauri::mobile_entry_point`) share one entry point.

// No console window in a release build.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    capsi_lib::run();
}