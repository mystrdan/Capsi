// Capsi - Tauri shell entry point (desktop + mobile).
//
// Thin layer over capsi_core: boots the runtime, wires commands into JS,
// and - on desktop only - keeps a system tray alive while minimised.

pub mod commands;

use tauri::Manager;

fn build_app() -> tauri::Builder<tauri::Wry> {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let handle = app.handle().clone();
            #[cfg(desktop)]
            {
                setup_tray(&handle).map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;
            }
            std::thread::spawn(move || {
                let rt = match tokio::runtime::Runtime::new() {
                    Ok(r) => r,
                    Err(e) => {
                        log::error!("capsi: cannot start tokio: {e}");
                        return;
                    }
                };
                rt.block_on(async {
                    if let Err(e) = crate::commands::app::bootstrap(handle).await {
                        log::error!("capsi: bootstrap failed: {e}");
                    }
                });
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            crate::commands::app::bootstrap,
            crate::commands::app::open_website,
            crate::commands::device::get_device_info,
            crate::commands::device::set_device_name,
            crate::commands::device::export_device_id,
            crate::commands::device::reset_device,
            crate::commands::trust::list_peers,
            crate::commands::trust::accept_peer,
            crate::commands::trust::ignore_peer,
            crate::commands::trust::forget_peer,
            crate::commands::trust::rename_peer,
            crate::commands::chat::list_conversations,
            crate::commands::chat::load_conversation,
            crate::commands::chat::send_message,
            crate::commands::chat::delete_conversation,
            crate::commands::chat::mark_read,
            crate::commands::files::offer_file,
            crate::commands::files::accept_file,
            crate::commands::files::decline_file,
            crate::commands::files::list_transfers,
            crate::commands::settings::get_settings,
            crate::commands::settings::save_settings,
            crate::commands::workplace::get_workplace,
            crate::commands::workplace::create_workplace,
            crate::commands::workplace::add_workplace_member,
            crate::commands::workplace::remove_workplace_member,
            crate::commands::workplace::create_workplace_department,
            crate::commands::workplace::assign_workplace_department,
            crate::commands::workplace::create_workplace_group,
            crate::commands::workplace::add_workplace_group_member,
            crate::commands::workplace::remove_workplace_group_member,
            crate::commands::workplace::delete_workplace_group,
            crate::commands::workplace::create_workplace_broadcast,
        ])
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    build_app()
        .run(tauri::generate_context!())
        .expect("capsi failed to start");
}

#[cfg(desktop)]
pub fn setup_tray(app: &tauri::AppHandle) -> Result<(), String> {
    use tauri::{
        menu::{Menu, MenuItem},
        tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    };
    let icon_bytes = include_bytes!("../icons/icon.png");
    let icon = tauri::image::Image::from_bytes(icon_bytes)
        .map_err(|e| format!("cannot load tray icon: {e}"))?;

    let show_item = MenuItem::with_id(app, "show", "Show Window", true, None::<&str>)
        .map_err(|e| format!("cannot build tray menu item: {e}"))?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit Capsi", true, None::<&str>)
        .map_err(|e| format!("cannot build tray menu item: {e}"))?;
    let menu = Menu::with_items(app, &[&show_item, &quit_item])
        .map_err(|e| format!("cannot build tray menu: {e}"))?;

    let _tray = TrayIconBuilder::new()
        .icon(icon)
        .menu(&menu)
        .tooltip("Capsi - LAN Messenger")
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)
        .map_err(|e| format!("cannot build tray icon: {e}"))?;

    Ok(())
}
