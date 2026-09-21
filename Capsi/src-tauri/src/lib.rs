// Capsi - Tauri shell entry point.
//
// This is the thinnest possible layer: it boots the Tauri runtime, wires the
// Rust commands from `capsi_core` into JavaScript, and keeps a system tray
// alive so Capsi keeps discovering peers while the window is minimised.

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};

pub mod commands;

/// Build the system tray icon and menu.
///
/// Called from `main` on the main thread, which is where Tauri expects menus and
/// tray icons to be created.
pub fn setup_tray(app: &AppHandle) -> Result<(), String> {
    // Load the tray icon PNG that was generated from the logo.
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
            "quit" => {
                app.exit(0);
            }
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
