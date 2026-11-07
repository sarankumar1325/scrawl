#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::{
    io::{Read, Write},
    net::{SocketAddr, TcpStream},
    path::PathBuf,
    process::{Child, Command, ExitStatus, Stdio},
    sync::{mpsc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tauri::{
    menu::{Menu, SubmenuBuilder},
    Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder,
};

const DEFAULT_PORT: u16 = 3779;
struct Server(Mutex<Option<Child>>);
struct RestartGate(Mutex<()>);

#[derive(Debug)]
enum ServerPoll {
    Stopped,
    Running,
    Exited(ExitStatus),
}

fn poll_server(server: &Server) -> Result<ServerPoll, String> {
    let mut guard = server.0.lock().map_err(|e| e.to_string())?;
    match guard.as_mut() {
        None => Ok(ServerPoll::Stopped),
        Some(child) => match child.try_wait().map_err(|e| e.to_string())? {
            None => Ok(ServerPoll::Running),
            Some(status) => {
                *guard = None;
                Ok(ServerPoll::Exited(status))
            }
        },
    }
}

fn monitor_server(app: tauri::AppHandle) {
    thread::spawn(move || loop {
        thread::sleep(Duration::from_millis(500));
        match poll_server(&app.state::<Server>()) {
            Ok(ServerPoll::Running) => continue,
            Ok(ServerPoll::Stopped) => return,
            result => {
                match result {
                    Ok(ServerPoll::Exited(status)) => {
                        eprintln!("Scrawl server exited unexpectedly: {status}")
                    }
                    Err(error) => eprintln!("Could not monitor Scrawl server: {error}"),
                    _ => unreachable!(),
                }
                // Keep the editor mounted: its in-memory changes can still be exported.
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.eval("window.scrawlServerStopped = true; window.dispatchEvent(new Event('scrawl:server-stopped'));");
                }
                return;
            }
        }
    });
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Settings {
    port: u16,
    data_directory: PathBuf,
}

impl Settings {
    fn validate(&self) -> Result<(), String> {
        if self.port < 1024 {
            return Err("Choose a port between 1024 and 65535.".into());
        }
        if !self.data_directory.is_absolute() {
            return Err("Enter an absolute path for the board folder.".into());
        }
        Ok(())
    }
}

fn settings_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_config_dir()
        .map_err(|e| e.to_string())?
        .join("settings.json"))
}

fn read_settings(app: &tauri::AppHandle) -> Result<Settings, String> {
    let path = settings_path(app)?;
    if path.exists() {
        let bytes = std::fs::read(&path).map_err(|e| format!("Cannot read settings: {e}"))?;
        let settings: Settings =
            serde_json::from_slice(&bytes).map_err(|e| format!("Cannot read settings: {e}"))?;
        settings.validate()?;
        Ok(settings)
    } else {
        Ok(Settings {
            port: DEFAULT_PORT,
            data_directory: app
                .path()
                .document_dir()
                .map_err(|e| e.to_string())?
                .join("Scrawl"),
        })
    }
}

fn log_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_log_dir()
        .map_err(|e| e.to_string())?
        .join("server.log"))
}

fn check_settings_window(window: &WebviewWindow) -> Result<(), String> {
    if window.label() == "settings" {
        Ok(())
    } else {
        Err("Only the settings window may access desktop controls.".into())
    }
}

#[tauri::command]
fn desktop_settings(window: WebviewWindow, app: tauri::AppHandle) -> Result<Settings, String> {
    check_settings_window(&window)?;
    read_settings(&app)
}

#[tauri::command]
fn save_desktop_settings(
    window: WebviewWindow,
    app: tauri::AppHandle,
    settings: Settings,
) -> Result<(), String> {
    check_settings_window(&window)?;
    settings.validate()?;
    let path = settings_path(&app)?;
    std::fs::create_dir_all(path.parent().ok_or("Invalid settings path")?)
        .map_err(|e| e.to_string())?;
    let temporary = path.with_extension("json.tmp");
    std::fs::write(
        &temporary,
        serde_json::to_vec_pretty(&settings).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    std::fs::rename(&temporary, &path).map_err(|e| format!("Could not save settings: {e}"))
}

#[tauri::command]
fn desktop_log(window: WebviewWindow, app: tauri::AppHandle) -> Result<String, String> {
    check_settings_window(&window)?;
    let text = std::fs::read_to_string(log_path(&app)?).unwrap_or_default();
    let tail: String = text
        .chars()
        .rev()
        .take(16_000)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    Ok(tail)
}

fn prepare_editor_restart(app: &tauri::AppHandle) -> Result<(), String> {
    let Some(main) = app.get_webview_window("main") else {
        return Ok(());
    };
    let url = main.url().map_err(|e| e.to_string())?;
    // The local startup-error page contains no editor or unsaved board.
    if url.path() == "/index.html"
        && (url.scheme() == "tauri" || url.host_str() == Some("tauri.localhost"))
    {
        return Ok(());
    }
    main.eval(r#"
        window.scrawlRestartState = 'pending';
        Promise.resolve().then(() => {
          if (!window.scrawl || !window.scrawl.prepareRestart) throw new Error('The editor is not ready.');
          return window.scrawl.prepareRestart();
        }).then(() => { window.scrawlRestartState = 'ready'; }, error => {
          window.scrawlRestartState = 'error:' + String(error && error.message || error);
        });
    "#).map_err(|e| format!("Could not ask the editor to save: {e}"))?;

    let deadline = Instant::now() + Duration::from_secs(15);
    let result = loop {
        let (tx, rx) = mpsc::channel();
        if let Err(error) = main.eval_with_callback(
            "window.scrawlRestartState || 'unavailable'",
            move |result| {
                let _ = tx.send(result);
            },
        ) {
            break Err(format!("Could not check the editor: {error}"));
        }
        match rx.recv_timeout(Duration::from_secs(1)) {
            Ok(value) => {
                let state = serde_json::from_str::<String>(&value)
                    .unwrap_or_else(|_| value.trim_matches('"').to_owned());
                if state == "ready" {
                    break Ok(());
                }
                if let Some(error) = state.strip_prefix("error:") {
                    break Err(error.to_owned());
                }
                if state != "pending" {
                    break Err("The editor could not confirm that its changes were saved.".into());
                }
            }
            Err(_) => break Err("The editor did not respond to the save request.".into()),
        }
        if Instant::now() >= deadline {
            break Err("The editor did not finish saving in time.".into());
        }
        thread::sleep(Duration::from_millis(100));
    };
    if result.is_err() {
        let _ = main.eval("document.body.inert = false;");
    }
    result
}

#[tauri::command]
async fn restart_desktop(window: WebviewWindow, app: tauri::AppHandle) -> Result<(), String> {
    check_settings_window(&window)?;
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<RestartGate>();
        let _guard = state
            .0
            .try_lock()
            .map_err(|_| "A restart is already in progress.".to_string())?;
        prepare_editor_restart(&app)?;
        stop(&app);
        app.restart()
    })
    .await
    .map_err(|error| format!("Restart failed: {error}"))?
}

fn open_settings(app: &tauri::AppHandle) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window("settings") {
        window.show()?;
        window.set_focus()?;
    } else {
        WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("settings.html".into()))
            .title("Scrawl Settings")
            .inner_size(680.0, 660.0)
            .min_inner_size(480.0, 420.0)
            .build()?;
    }
    Ok(())
}

fn open_window(app: &tauri::AppHandle, url: WebviewUrl, error: Option<&str>) -> tauri::Result<()> {
    let mut builder = WebviewWindowBuilder::new(app, "main", url)
        .title("Scrawl")
        .inner_size(1320.0, 860.0)
        .min_inner_size(960.0, 640.0);
    if let Some(message) = error {
        let encoded =
            serde_json::to_string(message).unwrap_or_else(|_| "\"Startup failed\"".into());
        builder = builder.initialization_script(format!("window.scrawlStartupError = {encoded};"));
    }
    builder.build()?;
    Ok(())
}

fn start(app: &tauri::AppHandle, settings: &Settings) -> Result<(), String> {
    let runtime = app
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?
        .join("desktop-runtime");
    let node = runtime.join(if cfg!(windows) { "node.exe" } else { "node" });
    let app_dir = runtime.join("app");
    let data = &settings.data_directory;
    let port = settings.port;
    std::fs::create_dir_all(&data).map_err(|e| format!("Cannot create {}: {e}", data.display()))?;
    let instance = format!(
        "{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let log = log_path(app)?;
    std::fs::create_dir_all(log.parent().ok_or("Invalid log path")?).map_err(|e| e.to_string())?;
    let output = std::fs::File::create(&log).map_err(|e| format!("Cannot open server log: {e}"))?;
    let errors = output.try_clone().map_err(|e| e.to_string())?;
    let mut command = Command::new(node);
    command
        .arg(app_dir.join("dist/server/index.js"))
        .current_dir(&app_dir)
        .env("PORT", port.to_string())
        .env("HOST", "127.0.0.1")
        .env("PUBLIC_URL", format!("http://localhost:{port}"))
        .env("DATA_DIR", data)
        .env("SCRAWL_DESKTOP_INSTANCE", &instance)
        .env("NODE_ENV", "production")
        .env_remove("ALLOWED_HOSTS")
        .stdin(Stdio::null())
        .stdout(Stdio::from(output))
        .stderr(Stdio::from(errors));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    let child = command
        .spawn()
        .map_err(|e| format!("Could not start the bundled server: {e}"))?;
    *app.state::<Server>().0.lock().map_err(|e| e.to_string())? = Some(child);

    for _ in 0..100 {
        {
            let state = app.state::<Server>();
            let mut guard = state.0.lock().map_err(|e| e.to_string())?;
            if let Some(child) = guard.as_mut() {
                if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
                    *guard = None;
                    return Err(format!("The server exited ({status}). Port {port} may already be in use. Open Server → Settings and logs for details or to change the port."));
                }
            }
        }
        let address = SocketAddr::from(([127, 0, 0, 1], port));
        if let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_millis(100)) {
            let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
            let _ = write!(
                stream,
                "GET /healthz HTTP/1.1\r\nHost: localhost:{port}\r\nConnection: close\r\n\r\n"
            );
            let mut response = String::new();
            let _ = stream.read_to_string(&mut response);
            if response.to_ascii_lowercase().contains(&format!(
                "x-scrawl-instance: {}",
                instance.to_ascii_lowercase()
            )) {
                return Ok(());
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    Err(format!("The server did not become ready. Check port {port} and open Server → Settings and logs for details."))
}

fn stop(app: &tauri::AppHandle) {
    if let Ok(mut guard) = app.state::<Server>().0.lock() {
        if let Some(mut child) = guard.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

fn main() {
    let app = tauri::Builder::default()
        .manage(Server(Mutex::new(None)))
        .manage(RestartGate(Mutex::new(())))
        .invoke_handler(tauri::generate_handler![
            desktop_settings,
            save_desktop_settings,
            desktop_log,
            restart_desktop
        ])
        .on_menu_event(|app, event| {
            if event.id().as_ref() == "scrawl-settings" {
                let _ = open_settings(app);
            }
        })
        .setup(|app| {
            let menu = Menu::default(app.handle())?;
            let server_menu = SubmenuBuilder::new(app, "Server")
                .text("scrawl-settings", "Settings and logs…")
                .build()?;
            menu.append(&server_menu)?;
            app.set_menu(menu)?;
            let handle = app.handle().clone();
            thread::spawn(move || {
                if let Err(error) = read_settings(&handle).and_then(|settings| {
                    start(&handle, &settings)?;
                    let url = tauri::Url::parse(&format!("http://127.0.0.1:{}", settings.port))
                        .map_err(|e| e.to_string())?;
                    open_window(&handle, WebviewUrl::External(url), None)
                        .map_err(|e| e.to_string())?;
                    monitor_server(handle.clone());
                    Ok(())
                }) {
                    stop(&handle);
                    eprintln!("Scrawl startup error: {error}");
                    let _ =
                        open_window(&handle, WebviewUrl::App("index.html".into()), Some(&error));
                }
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("failed to initialize Scrawl");
    app.run(|handle, event| {
        if matches!(event, tauri::RunEvent::Exit) {
            stop(handle);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::{poll_server, Server, ServerPoll, Settings};
    use std::path::PathBuf;
    use std::process::{Command, Stdio};
    use std::sync::Mutex;
    use std::time::{Duration, Instant};

    #[test]
    fn rejects_privileged_ports_and_relative_folders() {
        let absolute = std::env::temp_dir();
        assert!(Settings {
            port: 3779,
            data_directory: absolute.clone()
        }
        .validate()
        .is_ok());
        assert!(Settings {
            port: 80,
            data_directory: absolute
        }
        .validate()
        .is_err());
        assert!(Settings {
            port: 3779,
            data_directory: PathBuf::from("relative-folder")
        }
        .validate()
        .is_err());
    }

    #[test]
    fn settings_round_trip_preserves_folder_and_port() {
        let original = Settings {
            port: 43831,
            data_directory: std::env::temp_dir().join("Scrawl boards"),
        };
        let json = serde_json::to_vec(&original).unwrap();
        let decoded: Settings = serde_json::from_slice(&json).unwrap();
        assert_eq!(decoded.port, original.port);
        assert_eq!(decoded.data_directory, original.data_directory);
    }

    #[test]
    fn detects_unexpected_server_exit_and_clears_the_child() {
        #[cfg(windows)]
        let mut command = {
            let mut command = Command::new("cmd");
            command.args(["/C", "exit", "7"]);
            command
        };
        #[cfg(not(windows))]
        let mut command = {
            let mut command = Command::new("sh");
            command.args(["-c", "exit 7"]);
            command
        };
        let child = command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let server = Server(Mutex::new(Some(child)));
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            match poll_server(&server).unwrap() {
                ServerPoll::Running if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(10))
                }
                ServerPoll::Exited(status) => {
                    assert_eq!(status.code(), Some(7));
                    break;
                }
                state => panic!("unexpected state: {state:?}"),
            }
        }
        assert!(matches!(poll_server(&server).unwrap(), ServerPoll::Stopped));
    }
}
