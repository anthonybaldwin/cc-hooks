// CC Hooks — macOS notification system
//
// Single binary with subcommands, called by Claude Code hooks (settings.json):
//   on-submit  — UserPromptSubmit hook. Saves session state (timestamp, cwd,
//                terminal app) to a temp file for notify to read later.
//                No watcher needed — macOS notification clicks handle focus
//                directly via NSWorkspace activation.
//   notify     — Notification/Stop hook. Shows a native macOS notification
//                with project name, elapsed time, and action buttons.
//                Body click = focus terminal. "Open in Editor" button = launch editor.
//                Notifications replace by session ID (no stacking).
//   on-end     — SessionEnd hook. Cleans up temp files.
//   install    — Merges hook config into ~/.claude/settings.json.
//   uninstall  — Removes hooks from ~/.claude/settings.json, cleans temp files.
//
// Config: ../config.json (relative to binary). See config.json.example.
//   terminal: "ghostty" | "iterm2" | "terminal" (app to focus on click)
//   editor:   "zed" | "code" | "cursor" (app to open project in)
//
// State: /tmp/claude-timer-{session_id}.txt (pipe-delimited session data)

import Foundation
import UserNotifications
import AppKit

// MARK: - Config

struct Config: Decodable {
    var terminal: String?
    var editor: String?
    var messages: Messages?
    var icons: Icons?

    struct Messages: Decodable {
        var notification: String?
        var stop: String?
    }

    struct Icons: Decodable {
        var notification: String?
        var stop: String?
    }
}

func loadConfig(baseDir: String) -> Config {
    let path = (baseDir as NSString).appendingPathComponent("config.json")
    guard let data = FileManager.default.contents(atPath: path),
          let config = try? JSONDecoder().decode(Config.self, from: data)
    else { return Config() }
    return config
}

// MARK: - Helpers

func readStdin() -> [String: Any]? {
    guard let data = try? FileHandle.standardInput.availableData,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return json
}

func nowMs() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
}

func formatElapsed(_ ms: UInt64) -> String {
    let s = ms / 1000
    if s < 1 { return "(<1s)" }
    if s < 60 { return "(\(s)s)" }
    if s < 3600 { return "(\(s/60)m \(s%60)s)" }
    return "(\(s/3600)h \(s/60%60)m)"
}

/// Maps config terminal name to macOS app name
func terminalAppName(_ terminal: String) -> String {
    switch terminal.lowercased() {
    case "ghostty": return "Ghostty"
    case "iterm", "iterm2": return "iTerm2"
    case "terminal": return "Terminal"
    default: return terminal
    }
}

/// Maps config editor name to macOS app name
func editorAppName(_ editor: String) -> String {
    switch editor.lowercased() {
    case "zed": return "Zed"
    case "code", "vscode": return "Visual Studio Code"
    case "cursor": return "Cursor"
    default: return editor
    }
}

// MARK: - Temp files

func timerPath(_ sid: String) -> String { "/tmp/claude-timer-\(sid).txt" }

func timerWrite(_ sid: String, _ data: String) {
    try? data.write(toFile: timerPath(sid), atomically: true, encoding: .utf8)
}

func timerRead(_ sid: String) -> [String]? {
    guard let content = try? String(contentsOfFile: timerPath(sid), encoding: .utf8)
    else { return nil }
    return content.components(separatedBy: "|")
}

func timerDelete(_ sid: String) {
    try? FileManager.default.removeItem(atPath: timerPath(sid))
}

// MARK: - Subcommands

func onSubmit(baseDir: String) -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    let config = loadConfig(baseDir: baseDir)
    let cwd = FileManager.default.currentDirectoryPath
    let ts = nowMs()
    let terminal = config.terminal ?? "ghostty"

    // Save session state: timestamp|cwd|terminal|editor
    let editor = config.editor ?? "zed"
    timerWrite(sid, "\(ts)|\(cwd)|\(terminal)|\(editor)")

    return 0
}

func notify(hookEvent: String, baseDir: String) -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    let jsonCwd = json["cwd"] as? String

    guard let timer = timerRead(sid), timer.count >= 3
    else { return 0 }

    let startMs = UInt64(timer[0]) ?? 0
    let cwd = jsonCwd ?? timer[1]
    let terminal = timer[2]
    let editor = timer.count > 3 ? timer[3] : "zed"
    let dir = (cwd as NSString).lastPathComponent

    let config = loadConfig(baseDir: baseDir)
    let elapsed = formatElapsed(nowMs() - startMs)

    let message: String
    if hookEvent == "stop" {
        message = config.messages?.stop ?? "Task completed"
    } else {
        message = config.messages?.notification ?? "Claude needs your input"
    }

    // Request notification permission and show
    let center = UNUserNotificationCenter.current()
    let semaphore = DispatchSemaphore(value: 0)

    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { semaphore.signal(); return }

        let content = UNMutableNotificationContent()
        content.title = dir
        content.body = "\(message) \(elapsed)"
        content.sound = .default
        content.categoryIdentifier = "CLAUDE_NOTIFICATION"

        // Pass state in userInfo so the delegate can act on click
        content.userInfo = [
            "terminal": terminal,
            "editor": editor,
            "cwd": cwd
        ]

        // Icon from config (notification or stop)
        let iconFile: String
        if hookEvent == "stop" {
            iconFile = config.icons?.stop ?? "icons/stop.png"
        } else {
            iconFile = config.icons?.notification ?? "icons/notification.png"
        }
        let iconPath = (baseDir as NSString).appendingPathComponent(iconFile)
        if FileManager.default.fileExists(atPath: iconPath),
           let attachment = try? UNNotificationAttachment(
               identifier: "icon",
               url: URL(fileURLWithPath: iconPath),
               options: nil
           ) {
            content.attachments = [attachment]
        }

        // Replace previous notification for this session
        let request = UNNotificationRequest(
            identifier: "claude-\(sid)",
            content: content,
            trigger: nil
        )

        center.add(request) { _ in semaphore.signal() }
    }

    // Register actions: "Open in Editor" button
    let editorAction = UNNotificationAction(
        identifier: "OPEN_EDITOR",
        title: "Open in \(editorAppName(editor))",
        options: .foreground
    )
    let category = UNNotificationCategory(
        identifier: "CLAUDE_NOTIFICATION",
        actions: [editorAction],
        intentIdentifiers: [],
        options: .customDismissAction
    )
    center.setNotificationCategories([category])

    // Set delegate to handle clicks
    let delegate = NotificationDelegate()
    center.delegate = delegate

    semaphore.wait()

    // Keep alive briefly so the notification can be delivered
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))

    return 0
}

func onEnd() -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    timerDelete(sid)
    return 0
}

// MARK: - Notification delegate (handles click actions)

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Called when user clicks the notification body
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let terminal = userInfo["terminal"] as? String ?? "ghostty"
        let editor = userInfo["editor"] as? String ?? "zed"
        let cwd = userInfo["cwd"] as? String ?? ""

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // Body clicked — focus terminal
            let appName = terminalAppName(terminal)
            NSWorkspace.shared.launchApplication(appName)

        case "OPEN_EDITOR":
            // "Open in Editor" button clicked
            let appName = editorAppName(editor)
            if !cwd.isEmpty {
                NSWorkspace.shared.open(
                    [URL(fileURLWithPath: cwd)],
                    withApplicationAt: URL(fileURLWithPath: "/Applications/\(appName).app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                NSWorkspace.shared.launchApplication(appName)
            }

        default:
            break
        }

        completionHandler()
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Install / Uninstall (manages ~/.claude/settings.json)

func settingsPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return (home as NSString).appendingPathComponent(".claude/settings.json")
}

func installHooks(exePath: String) -> Int32 {
    let path = settingsPath()
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    var settings: [String: Any] = [:]
    if let data = FileManager.default.contents(atPath: path),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        settings = json
    }

    let hookEvents: [(String, String, Bool)] = [
        ("UserPromptSubmit", "\(exePath) on-submit", false),
        ("Notification", "\(exePath) notify notification", false),
        ("Stop", "\(exePath) notify stop", false),
        ("SessionEnd", "\(exePath) on-end", false),
    ]

    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    for (event, command, _) in hookEvents {
        hooks[event] = [
            ["matcher": "", "hooks": [["type": "command", "command": command]]]
        ]
    }
    settings["hooks"] = hooks

    guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
          let json = String(data: data, encoding: .utf8)
    else { return 1 }

    try? json.write(toFile: path, atomically: true, encoding: .utf8)
    print("Updated \(path)")
    return 0
}

func uninstallHooks() -> Int32 {
    // Clean temp files
    let tmpDir = NSTemporaryDirectory()
    if let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) {
        for file in files where file.hasPrefix("claude-timer-") {
            try? FileManager.default.removeItem(atPath: (tmpDir as NSString).appendingPathComponent(file))
        }
    }

    // Remove hooks from settings.json
    let path = settingsPath()
    guard let data = FileManager.default.contents(atPath: path),
          var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          var hooks = settings["hooks"] as? [String: Any]
    else {
        print("Uninstalled")
        return 0
    }

    for event in ["UserPromptSubmit", "Notification", "Stop", "SessionEnd"] {
        guard let entries = hooks[event] as? [[String: Any]] else { continue }
        let filtered = entries.filter { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return true }
            return !hookList.contains { ($0["command"] as? String ?? "").contains("notifications") }
        }
        if filtered.isEmpty { hooks.removeValue(forKey: event) }
        else { hooks[event] = filtered }
    }

    if hooks.isEmpty { settings.removeValue(forKey: "hooks") }
    else { settings["hooks"] = hooks }

    if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    print("Uninstalled")
    return 0
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: notifications <on-submit|notify|on-end|install|uninstall>\n", stderr)
    exit(1)
}

// baseDir = parent of the directory containing the binary
let exePath = (args[0] as NSString).resolvingSymlinksInPath
let binDir = (exePath as NSString).deletingLastPathComponent
let baseDir = (binDir as NSString).deletingLastPathComponent

let code: Int32
switch args[1] {
case "on-submit":
    code = onSubmit(baseDir: baseDir)
case "notify":
    let event = args.count > 2 ? args[2] : "notification"
    code = notify(hookEvent: event, baseDir: baseDir)
case "on-end":
    code = onEnd()
case "install":
    code = installHooks(exePath: exePath)
case "uninstall":
    code = uninstallHooks()
default:
    fputs("Unknown: \(args[1])\n", stderr)
    code = 1
}

exit(code)
