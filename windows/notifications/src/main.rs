#![windows_subsystem = "windows"]

// CC Hooks — Windows notification system (Rust)
//
// Single exe with subcommands, called by Claude Code hooks in settings.json:
//   on-submit    — saves session state (timer, WT PID, tab ID), then runs focus watcher loop
//                  (async: true in settings.json so Claude doesn't wait)
//   notify       — shows toast notification via WinRT API
//   on-end       — kills watcher, cleans up temp files
//   trigger      — protocol handler for claude-focus:// (creates trigger file for watcher)
//   editor       — protocol handler for claude-editor:// (launches configured editor)
//
// Reads config from ../config.json (relative to bin/).
// Reads icons from ../icons/ (relative to bin/).
// Stores session data in %TEMP%/claude-timer-{session_id}.txt

use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Read;
use std::mem::size_of;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use serde::Deserialize;
use windows::core::*;
use windows::Data::Xml::Dom::XmlDocument;
use windows::UI::Notifications::*;
use windows::Win32::Foundation::*;
use windows::Win32::System::Com::*;
use windows::Win32::System::Diagnostics::ToolHelp::*;
use windows::Win32::System::Ole::*;
use windows::Win32::System::Threading::*;
use windows::Win32::System::Variant::VARIANT;
use windows::Win32::UI::Accessibility::*;
use windows::Win32::UI::WindowsAndMessaging::*;

// Application User Model ID — must match the AUMID set on the Start Menu shortcut
// by install.ps1. Windows uses this to associate toasts with the shortcut's name/icon.
const AUMID: &str = "ClaudeCode.Hooks";

// ═══════════════════════════════════════
// Config — read from config.json
// ═══════════════════════════════════════

#[derive(Deserialize, Default)]
struct Config {
    editor: Option<String>,
    messages: Option<Messages>,
    icons: Option<Icons>,
}

#[derive(Deserialize, Default)]
struct Messages {
    notification: Option<String>,
    stop: Option<String>,
}

#[derive(Deserialize, Default)]
struct Icons {
    notification: Option<String>,
    stop: Option<String>,
}

// ═══════════════════════════════════════
// Entry point
// ═══════════════════════════════════════

fn main() -> ExitCode {
    let exe = env::current_exe().unwrap_or_default();
    let bin_dir = exe.parent().unwrap_or(Path::new("."));
    let base_dir = bin_dir.parent().unwrap_or(Path::new(".")).to_path_buf();

    let config: Config = fs::read_to_string(base_dir.join("config.json"))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();

    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: notifications <on-submit|notify|on-end|trigger|editor>");
        return ExitCode::from(1);
    }

    let code = match args[1].as_str() {
        "on-submit" => on_submit(&base_dir),
        "notify" => notify(args.get(2).map(|s| s.as_str()).unwrap_or("notification"), &base_dir, &config),
        "on-end" => on_end(),
        "trigger" => trigger(args.get(2).map(|s| s.as_str()).unwrap_or("")),
        "editor" => open_editor(args.get(2).map(|s| s.as_str()).unwrap_or(""), &config),
        other => { eprintln!("Unknown: {other}"); 1 }
    };

    ExitCode::from(code as u8)
}

// ═══════════════════════════════════════
// on-submit — called on every user message (UserPromptSubmit hook, async: true)
//
// Because this process is a child of WT's process tree (bash → claude → WT),
// UI Automation tab selection (SelectionItemPattern.Select()) works directly.
// No WMI/VBS detachment needed — async: true prevents blocking Claude.
// ═══════════════════════════════════════

fn on_submit(_base_dir: &Path) -> i32 {
    let json = match read_stdin() { Some(j) => j, None => return 1 };
    let sid = match json.get("session_id").and_then(|v| v.as_str()) { Some(s) => s.to_string(), None => return 1 };

    let cwd = env::current_dir().unwrap_or_default().to_string_lossy().to_string();
    let ts = now_ms();

    let (wt_pid, claude_pid) = find_ancestors();
    if wt_pid == 0 { return 0; } // Not in Windows Terminal (IDE like Zed)

    // Find selected tab on STA thread (UI Automation requires COM STA)
    let wt = wt_pid;
    let (tab_rid, tab_name) = run_on_sta(move || find_selected_tab(wt))
        .map(|(rid, raw)| {
            // Strip spinner characters (braille patterns U+2800..U+28FF) from tab title
            let name = raw.trim_start_matches(|c: char| ('\u{2800}'..='\u{28FF}').contains(&c) || c == ' ').to_string();
            (rid, name)
        })
        .unwrap_or_default();

    // Save session state: timestamp|wtPid|claudePid|cwd|tabRuntimeId|tabName
    timer_write(&sid, &format!("{ts}|{wt_pid}|{claude_pid}|{cwd}|{tab_rid}|{tab_name}"));

    // Save our PID so the next on-submit call can kill us
    let _ = fs::write(watcher_pid_path(&sid), std::process::id().to_string());

    // Run watcher loop (async: true on hook means Claude won't wait)
    watch_for_trigger(&sid, wt_pid, claude_pid, &tab_rid);

    0
}

// ═══════════════════════════════════════
// notify — shows toast notification via WinRT API
// ═══════════════════════════════════════

fn notify(hook_event: &str, base_dir: &Path, config: &Config) -> i32 {
    let json = match read_stdin() { Some(j) => j, None => return 1 };
    let sid = match json.get("session_id").and_then(|v| v.as_str()) { Some(s) => s.to_string(), None => return 1 };
    let json_cwd = json.get("cwd").and_then(|v| v.as_str()).map(String::from);

    let timer = match timer_read(&sid) { Some(t) => t, None => return 0 };
    let wt_pid: u32 = timer.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    if wt_pid == 0 { return 0; } // IDE, skip

    let cwd = timer.get(3).cloned().unwrap_or_default();
    let dir = Path::new(json_cwd.as_deref().unwrap_or(&cwd))
        .file_name().unwrap_or_default().to_string_lossy().to_string();

    // Elapsed time since last user message
    let start_ms: u64 = timer.first().and_then(|s| s.parse().ok()).unwrap_or(0);
    let s = (now_ms().saturating_sub(start_ms)) / 1000;
    let elapsed = if s < 1 { "(<1s)".into() }
        else if s < 60 { format!("({s}s)") }
        else if s < 3600 { format!("({}m {}s)", s / 60, s % 60) }
        else { format!("({}h {}m)", s / 3600, s / 60 % 60) };

    let message = if hook_event == "stop" {
        config.messages.as_ref().and_then(|m| m.stop.as_deref()).unwrap_or("Task completed")
    } else {
        config.messages.as_ref().and_then(|m| m.notification.as_deref()).unwrap_or("Claude needs your input")
    };

    let icon_file = if hook_event == "stop" {
        config.icons.as_ref().and_then(|i| i.stop.as_deref()).unwrap_or("icons/stop.png")
    } else {
        config.icons.as_ref().and_then(|i| i.notification.as_deref()).unwrap_or("icons/notification.png")
    };
    let icon_path = base_dir.join(icon_file);
    let icon_str = icon_path.to_string_lossy().replace('\\', "/");

    let focus_uri = format!("claude-focus://{sid}");
    let (editor_uri, editor_label) = match config.editor.as_deref() {
        Some(ed) if !ed.is_empty() => (
            format!("claude-editor://{}", cwd.replace('\\', "/")),
            format!("Open in {}{}", ed[..1].to_uppercase(), &ed[1..]),
        ),
        _ => (String::new(), String::new()),
    };

    let icon_xml = if icon_path.exists() {
        format!(r#"<image placement="appLogoOverride" src="file:///{icon_str}" />"#)
    } else { String::new() };

    let editor_xml = if !editor_uri.is_empty() {
        format!(r#"<action content="{}" arguments="{}" activationType="protocol" />"#,
            esc(&editor_label), esc(&editor_uri))
    } else { String::new() };

    let xml = format!(
r#"<toast launch="{focus}" activationType="protocol">
  <visual><binding template="ToastGeneric">
    <text>{dir}</text>
    <text>{msg} {elapsed}</text>
    {icon}
  </binding></visual>
  <actions>
    <action content="Focus Terminal" arguments="{focus}" activationType="protocol" />
    {editor}
  </actions>
</toast>"#,
        focus = esc(&focus_uri), dir = esc(&dir), msg = esc(message),
        elapsed = esc(&elapsed), icon = icon_xml, editor = editor_xml,
    );

    show_toast(&xml, &sid)
}

fn show_toast(xml_str: &str, sid: &str) -> i32 {
    let doc = XmlDocument::new().ok();
    let Some(doc) = doc else { return 1 };
    if doc.LoadXml(&HSTRING::from(xml_str)).is_err() { return 1; }

    let Ok(toast) = ToastNotification::CreateToastNotification(&doc) else { return 1 };
    let tag = if sid.len() > 64 { &sid[..64] } else { sid };
    let _ = toast.SetTag(&HSTRING::from(tag));

    let Ok(notifier) = ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(AUMID)) else { return 1 };
    if notifier.Show(&toast).is_err() { return 1; }
    0
}

// ═══════════════════════════════════════
// on-end — kills watcher, cleans up temp files
// ═══════════════════════════════════════

fn on_end() -> i32 {
    let json = match read_stdin() { Some(j) => j, None => return 1 };
    let sid = match json.get("session_id").and_then(|v| v.as_str()) { Some(s) => s, None => return 1 };
    kill_watcher(sid);
    timer_delete(sid);
    trigger_delete(sid);
    watcher_pid_delete(sid);
    0
}

// ═══════════════════════════════════════
// trigger — protocol handler for claude-focus://
//
// Called by Windows when the "Focus Terminal" button is clicked on a toast.
// Creates a trigger file that the watcher polls for.
// ═══════════════════════════════════════

fn trigger(uri: &str) -> i32 {
    let sid = uri.replace("claude-focus://", "");
    let sid = sid.trim_end_matches('/');
    if sid.is_empty() { return 1; }
    let _ = fs::write(trigger_path(sid), "");
    0
}

// ═══════════════════════════════════════
// editor — protocol handler for claude-editor://
//
// Called by Windows when the "Open in Editor" button is clicked on a toast.
// Launches the configured editor with the project directory.
// ═══════════════════════════════════════

fn open_editor(uri: &str, config: &Config) -> i32 {
    let path = uri.replace("claude-editor://", "").trim_end_matches('/').replace('/', "\\");
    let editor = match config.editor.as_deref() { Some(e) if !e.is_empty() => e, _ => return 1 };
    if path.is_empty() { return 1; }
    let p = Path::new(&path);
    if !p.exists() { return 1; }
    let work_dir = if p.is_dir() { p } else { p.parent().unwrap_or(Path::new(".")) };
    let _ = std::process::Command::new(editor).arg(&path).current_dir(work_dir).spawn();
    0
}

// ═══════════════════════════════════════
// Focus watcher — polls for trigger file, focuses WT window + selects tab
// ═══════════════════════════════════════

fn watch_for_trigger(sid: &str, wt_pid: u32, claude_pid: u32, tab_rid: &str) {
    let sid = sid.to_string();
    let tab_rid = tab_rid.to_string();

    // Run on STA thread (required for UI Automation COM calls)
    let _ = run_on_sta(move || {
        let trigger = trigger_path(&sid);
        let mut last_focus: u64 = 0;

        loop {
            if !process_alive(wt_pid) { return; }
            if claude_pid != 0 && !process_alive(claude_pid) { return; }

            if trigger.exists() {
                let _ = fs::remove_file(&trigger);

                // Debounce: skip if focused within last 2 seconds
                let now = now_ms();
                if now - last_focus < 2000 { thread::sleep(Duration::from_millis(200)); continue; }
                last_focus = now;

                focus_terminal(wt_pid, &tab_rid);
            }

            thread::sleep(Duration::from_millis(200));
        }
    });
}

fn focus_terminal(wt_pid: u32, tab_rid: &str) {
    unsafe {
        let Ok(auto) = create_automation() else { return };
        let Ok(root) = auto.GetRootElement() else { return };

        let Ok(pid_cond) = auto.CreatePropertyCondition(
            UIA_ProcessIdPropertyId, &VARIANT::from(wt_pid as i32),
        ) else { return };
        let Ok(tab_cond) = auto.CreatePropertyCondition(
            UIA_ControlTypePropertyId, &VARIANT::from(UIA_TabItemControlTypeId.0),
        ) else { return };

        let Ok(windows) = root.FindAll(TreeScope_Children, &pid_cond) else { return };
        for i in 0..windows.Length().unwrap_or(0) {
            let Ok(win) = windows.GetElement(i) else { continue };
            let Ok(tabs) = win.FindAll(TreeScope_Descendants, &tab_cond) else { continue };

            for j in 0..tabs.Length().unwrap_or(0) {
                let Ok(tab) = tabs.GetElement(j) else { continue };

                let rid = get_runtime_id(&tab);
                if !tab_rid.is_empty() && rid != tab_rid { continue; }

                let hwnd = HWND(win.CurrentNativeWindowHandle().unwrap_or_default().0);
                let _ = ShowWindow(hwnd, SW_RESTORE);
                let _ = SetForegroundWindow(hwnd);

                if !tab_rid.is_empty() {
                    thread::sleep(Duration::from_millis(200));
                    if let Ok(pattern) = tab.GetCurrentPattern(UIA_SelectionItemPatternId) {
                        if let Ok(sip) = pattern.cast::<IUIAutomationSelectionItemPattern>() {
                            let _ = sip.Select();
                        }
                    }
                }
                return;
            }
        }
    }
}

// ═══════════════════════════════════════
// Process helpers — uses CreateToolhelp32Snapshot instead of WMI
// ═══════════════════════════════════════

fn find_ancestors() -> (u32, u32) {
    let (mut wt_pid, mut claude_pid) = (0u32, 0u32);
    let procs = snapshot_processes();

    // Walk from current process upward through parent chain
    let mut pid = std::process::id();
    loop {
        let Some((parent, _)) = procs.get(&pid) else { break };
        pid = *parent;
        let Some((_, name)) = procs.get(&pid) else { break };
        let base = name.strip_suffix(".exe").unwrap_or(name);
        if base.eq_ignore_ascii_case("claude") { claude_pid = pid; }
        if base.eq_ignore_ascii_case("WindowsTerminal") { wt_pid = pid; break; }
    }

    (wt_pid, claude_pid)
}

fn snapshot_processes() -> HashMap<u32, (u32, String)> {
    let mut map = HashMap::new();
    unsafe {
        let Ok(snap) = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) else { return map };
        let mut pe = PROCESSENTRY32W { dwSize: size_of::<PROCESSENTRY32W>() as u32, ..Default::default() };

        if Process32FirstW(snap, &mut pe).is_ok() {
            loop {
                let len = pe.szExeFile.iter().position(|&c| c == 0).unwrap_or(pe.szExeFile.len());
                let name = String::from_utf16_lossy(&pe.szExeFile[..len]);
                map.insert(pe.th32ProcessID, (pe.th32ParentProcessID, name));
                if Process32NextW(snap, &mut pe).is_err() { break; }
            }
        }
        let _ = CloseHandle(snap);
    }
    map
}

fn process_alive(pid: u32) -> bool {
    unsafe {
        let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else { return false };
        let mut code = 0u32;
        let alive = GetExitCodeProcess(handle, &mut code).is_ok() && code == 259; // STILL_ACTIVE
        let _ = CloseHandle(handle);
        alive
    }
}

fn kill_watcher(sid: &str) {
    let path = watcher_pid_path(sid);
    let Ok(content) = fs::read_to_string(&path) else { return };
    let Ok(pid) = content.trim().parse::<u32>() else { return };
    if pid == std::process::id() { return; }
    unsafe {
        if let Ok(h) = OpenProcess(PROCESS_TERMINATE, false, pid) {
            let _ = TerminateProcess(h, 1);
            let _ = CloseHandle(h);
        }
    }
    let _ = fs::remove_file(&path);
}

// ═══════════════════════════════════════
// UI Automation helpers
// ═══════════════════════════════════════

fn create_automation() -> windows::core::Result<IUIAutomation> {
    unsafe { CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER) }
}

fn find_selected_tab(wt_pid: u32) -> (String, String) {
    unsafe {
        let Ok(auto) = create_automation() else { return Default::default() };
        let Ok(root) = auto.GetRootElement() else { return Default::default() };

        let Ok(pid_cond) = auto.CreatePropertyCondition(
            UIA_ProcessIdPropertyId, &VARIANT::from(wt_pid as i32),
        ) else { return Default::default() };
        let Ok(tab_cond) = auto.CreatePropertyCondition(
            UIA_ControlTypePropertyId, &VARIANT::from(UIA_TabItemControlTypeId.0),
        ) else { return Default::default() };

        let Ok(windows) = root.FindAll(TreeScope_Children, &pid_cond) else { return Default::default() };
        for i in 0..windows.Length().unwrap_or(0) {
            let Ok(win) = windows.GetElement(i) else { continue };
            let Ok(tabs) = win.FindAll(TreeScope_Descendants, &tab_cond) else { continue };

            for j in 0..tabs.Length().unwrap_or(0) {
                let Ok(tab) = tabs.GetElement(j) else { continue };
                if let Ok(pattern) = tab.GetCurrentPattern(UIA_SelectionItemPatternId) {
                    if let Ok(sip) = pattern.cast::<IUIAutomationSelectionItemPattern>() {
                        if sip.CurrentIsSelected().unwrap_or(BOOL::from(false)).as_bool() {
                            let rid = get_runtime_id(&tab);
                            let name = tab.CurrentName().map(|n| n.to_string()).unwrap_or_default();
                            return (rid, name);
                        }
                    }
                }
            }
        }

        Default::default()
    }
}

fn get_runtime_id(element: &IUIAutomationElement) -> String {
    unsafe {
        let Ok(sa) = element.GetRuntimeId() else { return String::new() };
        if sa.is_null() { return String::new(); }

        let lower = SafeArrayGetLBound(sa, 1).unwrap_or(0);
        let upper = SafeArrayGetUBound(sa, 1).unwrap_or(-1);

        let mut ids = Vec::new();
        for i in lower..=upper {
            let mut val: i32 = 0;
            if SafeArrayGetElement(sa, &i, &mut val as *mut _ as *mut std::ffi::c_void).is_ok() {
                ids.push(val.to_string());
            }
        }
        let _ = SafeArrayDestroy(sa);

        ids.join(",")
    }
}

/// Runs a closure on an STA thread (required for UI Automation COM calls).
fn run_on_sta<F, T>(f: F) -> std::result::Result<T, Box<dyn std::any::Any + Send>>
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
{
    thread::Builder::new()
        .spawn(move || {
            unsafe { let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED); }
            f()
        })
        .expect("failed to spawn STA thread")
        .join()
}

// ═══════════════════════════════════════
// Temp file helpers
// ═══════════════════════════════════════

// Timer file: stores session state as pipe-delimited values in %TEMP%.
// Format: timestamp|wtPid|claudePid|cwd|tabRuntimeId|tabName
fn timer_path(sid: &str) -> PathBuf { env::temp_dir().join(format!("claude-timer-{sid}.txt")) }
fn timer_write(sid: &str, data: &str) { let _ = fs::write(timer_path(sid), data); }
fn timer_read(sid: &str) -> Option<Vec<String>> {
    fs::read_to_string(timer_path(sid)).ok().map(|s| s.splitn(6, '|').map(String::from).collect())
}
fn timer_delete(sid: &str) { let _ = fs::remove_file(timer_path(sid)); }

// Trigger file: empty file in %TEMP%. Created by the protocol handler when the user
// clicks "Focus Terminal". The watcher polls for it every 200ms.
fn trigger_path(sid: &str) -> PathBuf { env::temp_dir().join(format!("claude-focus-trigger-{sid}")) }
fn trigger_delete(sid: &str) { let _ = fs::remove_file(trigger_path(sid)); }

// Watcher PID file: stores the PID of the on-submit watcher process so the next
// on-submit call (or on-end) can kill it.
fn watcher_pid_path(sid: &str) -> PathBuf { env::temp_dir().join(format!("claude-watcher-{sid}.txt")) }
fn watcher_pid_delete(sid: &str) { let _ = fs::remove_file(watcher_pid_path(sid)); }

// ═══════════════════════════════════════
// Misc helpers
// ═══════════════════════════════════════

fn read_stdin() -> Option<serde_json::Value> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf).ok()?;
    serde_json::from_str(&buf).ok()
}

/// Escapes special XML characters for toast XML attributes/content.
fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
