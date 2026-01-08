#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            // appDataDir al
            let app_data_dir = app.path().app_data_dir().unwrap();
            std::fs::create_dir_all(&app_data_dir).unwrap();

            let db_path = app_data_dir.join("pos.db");
            println!("✅ DB path: {:?}", db_path);

            #[cfg(debug_assertions)]
            {
                let window = app.get_webview_window("main").unwrap();
                window.open_devtools();
            }

            Ok(())
        })
        .plugin(tauri_plugin_sql::Builder::default().build())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
