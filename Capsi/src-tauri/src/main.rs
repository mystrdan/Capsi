// Capsi by CAPSICOM - "Download. Run. Connect."
//
// Thin Tauri shell over `capsi_core`. Boots the runtime, wires the Rust
// commands, and keeps a system tray so discovery keeps running when the
// window is minimised.

// No console window in a release build.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let handle = app.handle().clone();

            // The tray is built here, on the main thread, which is where Tauri
            // expects menus and tray icons to be created.
            capsi_lib::setup_tray(&handle)
                .map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;

            // Identity, the data directory and the discovery loop all want the
            // async runtime, so they get their own thread and report progress
            // through the `discovery-event` channel.
            std::thread::spawn(move || {
                let rt = match tokio::runtime::Runtime::new() {
                    Ok(r) => r,
                    Err(e) => {
                        log::error!("capsi: cannot start tokio: {e}");
                        return;
                    }
                };
                rt.block_on(async {
                    if let Err(e) = capsi_lib::commands::app::bootstrap(handle).await {
                        log::error!("capsi: bootstrap failed: {e}");
                    }
                });
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            capsi_lib::commands::app::bootstrap,
            capsi_lib::commands::device::get_device_info,
            capsi_lib::commands::device::set_device_name,
            capsi_lib::commands::device::export_device_id,
            capsi_lib::commands::device::reset_device,
            capsi_lib::commands::trust::list_peers,
            capsi_lib::commands::trust::accept_peer,
            capsi_lib::commands::trust::ignore_peer,
            capsi_lib::commands::trust::forget_peer,
            capsi_lib::commands::trust::rename_peer,
            capsi_lib::commands::chat::list_conversations,
            capsi_lib::commands::chat::load_conversation,
            capsi_lib::commands::chat::send_message,
            capsi_lib::commands::chat::delete_conversation,
            capsi_lib::commands::chat::mark_read,
            capsi_lib::commands::files::offer_file,
            capsi_lib::commands::files::accept_file,
            capsi_lib::commands::files::decline_file,
            capsi_lib::commands::files::list_transfers,
            capsi_lib::commands::settings::get_settings,
            capsi_lib::commands::settings::save_settings,
        ])
        .run(tauri::generate_context!())
        .expect("capsi failed to start");
}