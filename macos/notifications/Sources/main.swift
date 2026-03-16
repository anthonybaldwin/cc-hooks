// CC Hooks — macOS notification system
//
// Single binary with subcommands, called by Claude Code hooks (settings.json):
//   on-submit  — UserPromptSubmit hook. Captures session state (timestamp, cwd,
//                terminal, editor, tty) to a temp file for notify to read later.
//   notify     — Notification/Stop hook (async: true). Shows a native notification
//                via terminal-notifier. Blocks until click/dismiss, then dispatches
//                to focus or editor-open. Replaces by session ID (no stacking).
//   focus      — Focuses the correct terminal window/tab/pane using AppleScript.
//                Supports Ghostty (by cwd), iTerm2 (by tty), Terminal.app (by tty).
//   on-end     — SessionEnd hook. Cleans up temp files.
//   install    — Merges hook config into ~/.claude/settings.json.
//   uninstall  — Removes hooks from settings.json, cleans up temp files.
//
// Dependencies: terminal-notifier (`brew install terminal-notifier`)
//               Falls back to osascript (no click actions) if not installed.
//
// Config: ../config.json (relative to binary). See config.json.example.
//   terminal: "ghostty" | "iterm2" | "terminal" (app to focus on click)
//   editor:   "zed" | "code" | "cursor" (app to open project in)
//
// State: /tmp/claude-timer-{session_id}.txt (pipe-delimited session data)
//        /tmp/claude-notifier-{session_id}.txt (PID of terminal-notifier process)

import Foundation

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
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty,
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

/// Runs a shell command and returns stdout
@discardableResult
func shell(_ command: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// Finds the tty device by walking up the process tree
func findTty() -> String {
    var pid = ProcessInfo.processInfo.processIdentifier
    for _ in 0..<10 {
        let output = shell("ps -o tty=,ppid= -p \(pid)")
        let parts = output.split(separator: " ", maxSplits: 1)
        guard parts.count >= 2 else { break }
        let tty = String(parts[0])
        if tty != "??" && !tty.isEmpty && tty != "-" {
            return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        }
        pid = Int32(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        if pid <= 1 { break }
    }
    return ""
}

// MARK: - Temp files

func timerPath(_ sid: String) -> String { "/tmp/claude-timer-\(sid).txt" }
func notifierPidPath(_ sid: String) -> String { "/tmp/claude-notifier-\(sid).txt" }

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

func notifierPidDelete(_ sid: String) {
    try? FileManager.default.removeItem(atPath: notifierPidPath(sid))
}

/// Kills the previous terminal-notifier process for this session
func killPreviousNotifier(_ sid: String) {
    let path = notifierPidPath(sid)
    guard let content = try? String(contentsOfFile: path, encoding: .utf8),
          let pid = Int32(content.trimmingCharacters(in: .whitespaces)),
          pid > 0
    else { return }
    kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: path)
}

/// Captures the currently focused terminal session/tab ID via AppleScript.
/// Each terminal has a different API for this.
func captureTerminalId(_ terminal: String) -> String {
    switch terminal.lowercased() {
    case "ghostty":
        return shell("""
            osascript -e 'tell application "Ghostty" to return id of focused terminal of selected tab of front window' 2>/dev/null
            """)
    case "iterm", "iterm2":
        return shell("""
            osascript -e 'tell application "iTerm2" to return id of current session of current tab of current window' 2>/dev/null
            """)
    case "terminal":
        // Terminal.app doesn't have split panes — tty is sufficient
        return ""
    default:
        return ""
    }
}

// MARK: - on-submit

func onSubmit(baseDir: String) -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    let config = loadConfig(baseDir: baseDir)
    let cwd = FileManager.default.currentDirectoryPath
    let ts = nowMs()
    let terminal = config.terminal ?? "ghostty"
    let editor = config.editor ?? "zed"
    let tty = findTty()
    let terminalId = captureTerminalId(terminal)

    // Format: timestamp|cwd|terminal|editor|tty|terminalId
    timerWrite(sid, "\(ts)|\(cwd)|\(terminal)|\(editor)|\(tty)|\(terminalId)")

    return 0
}

// MARK: - notify (async: true — blocks until notification click/dismiss)

func notify(hookEvent: String, baseDir: String) -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    let jsonCwd = json["cwd"] as? String

    guard let timer = timerRead(sid), timer.count >= 4
    else { return 0 }

    let startMs = UInt64(timer[0]) ?? 0
    let cwd = timer[1].isEmpty ? (jsonCwd ?? "") : timer[1]
    let terminal = timer[2]
    let editor = timer[3]
    let tty = timer.count > 4 ? timer[4] : ""
    let terminalId = timer.count > 5 ? timer[5] : ""
    let dir = (cwd as NSString).lastPathComponent

    let config = loadConfig(baseDir: baseDir)
    let elapsed = formatElapsed(nowMs() - startMs)

    let message: String
    if hookEvent == "stop" {
        message = config.messages?.stop ?? "Task completed"
    } else {
        message = config.messages?.notification ?? "Claude needs your input"
    }

    // Kill previous notification for this session
    killPreviousNotifier(sid)

    // Icon: use config or default
    let iconFile: String
    if hookEvent == "stop" {
        iconFile = config.icons?.stop ?? "icons/stop.png"
    } else {
        iconFile = config.icons?.notification ?? "icons/notification.png"
    }
    let iconPath = (baseDir as NSString).appendingPathComponent(iconFile)

    // Map terminal to bundle ID for notification icon
    let senderBundleId: String
    switch terminal.lowercased() {
    case "ghostty": senderBundleId = "com.mitchellh.ghostty"
    case "iterm", "iterm2": senderBundleId = "com.googlecode.iterm2"
    case "terminal": senderBundleId = "com.apple.Terminal"
    default: senderBundleId = "com.mitchellh.ghostty"
    }

    let hasTerminalNotifier = !shell("which terminal-notifier").isEmpty

    if hasTerminalNotifier {
        // terminal-notifier: shows notification, blocks until click/dismiss,
        // prints which action was taken to stdout
        let exePath = CommandLine.arguments[0]
        var args = [
            "-title", dir,
            "-message", "\(message) \(elapsed)",
            "-group", "claude-\(sid)",
            "-sender", senderBundleId,
            "-actions", "Open in \(editorAppName(editor))",
        ]

        if FileManager.default.fileExists(atPath: iconPath) {
            args += ["-appIcon", iconPath]
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell("which terminal-notifier"))
        process.arguments = args
        process.standardOutput = pipe
        try? process.run()

        // Save PID so next notification can kill us
        try? "\(process.processIdentifier)".write(
            toFile: notifierPidPath(sid), atomically: true, encoding: .utf8)

        process.waitUntilExit()

        // Dispatch based on what was clicked
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch result {
        case "@CONTENTCLICKED":
            focusTerminal(terminal: terminal, cwd: cwd, tty: tty, terminalId: terminalId)
        case let action where action.hasPrefix("Open in"):
            // "Open in Editor" button clicked
            openEditor(editor: editor, cwd: cwd)
        default:
            break // Dismissed or timeout
        }
    } else {
        // Fallback: osascript (no click actions)
        shell("osascript -e 'display notification \"\(message) \(elapsed)\" with title \"\(dir)\"'")
    }

    notifierPidDelete(sid)
    return 0
}

// MARK: - focus (called directly or after notification click)
//
// Uses terminal-specific AppleScript to find and focus the exact tab/pane.
// Primary match: session ID captured during on-submit.
// Fallback: tty (iTerm2, Terminal.app) or working directory (Ghostty).

func focusTerminal(terminal: String, cwd: String, tty: String, terminalId: String) {
    switch terminal.lowercased() {
    case "ghostty":
        if !terminalId.isEmpty {
            // Match by saved terminal ID
            shell("""
                osascript -e '
                tell application "Ghostty"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with term in terminals of t
                                if id of term is "\(terminalId)" then
                                    focus term
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell'
                """)
        } else {
            // Fallback: match by working directory
            shell("""
                osascript -e '
                tell application "Ghostty"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with term in terminals of t
                                if working directory of term contains "\(cwd)" then
                                    focus term
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell'
                """)
        }

    case "iterm", "iterm2":
        if !terminalId.isEmpty {
            // Match by saved session ID
            shell("""
                osascript -e '
                tell application "iTerm2"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if id of s is "\(terminalId)" then
                                    select s
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell'
                """)
        } else if !tty.isEmpty {
            // Fallback: match by tty
            shell("""
                osascript -e '
                tell application "iTerm2"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(tty)" then
                                    select s
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell'
                """)
        } else {
            shell("osascript -e 'tell application \"iTerm2\" to activate'")
        }

    case "terminal":
        // Terminal.app has no split panes — tty matching is sufficient
        if !tty.isEmpty {
            shell("""
                osascript -e '
                tell application "Terminal"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(tty)" then
                                set selected tab of w to t
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell'
                """)
        } else {
            shell("osascript -e 'tell application \"Terminal\" to activate'")
        }

    default:
        let appName = terminalAppName(terminal)
        shell("osascript -e 'tell application \"\(appName)\" to activate'")
    }
}

func openEditor(editor: String, cwd: String) {
    let appName = editorAppName(editor)
    switch editor.lowercased() {
    case "zed":
        shell("open -a \"\(appName)\" \"\(cwd)\"")
    case "code", "vscode":
        shell("code \"\(cwd)\"")
    case "cursor":
        shell("cursor \"\(cwd)\"")
    default:
        shell("open -a \"\(appName)\" \"\(cwd)\"")
    }
}

// MARK: - on-end

func onEnd() -> Int32 {
    guard let json = readStdin(),
          let sid = json["session_id"] as? String
    else { return 1 }

    killPreviousNotifier(sid)
    timerDelete(sid)
    notifierPidDelete(sid)
    return 0
}

// MARK: - Install / Uninstall

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

    // Notification and Stop hooks are async because terminal-notifier blocks
    // until the user clicks/dismisses the notification.
    let hookEntries: [(String, String, Bool)] = [
        ("UserPromptSubmit", "\(exePath) on-submit", false),
        ("Notification", "\(exePath) notify notification", true),
        ("Stop", "\(exePath) notify stop", true),
        ("SessionEnd", "\(exePath) on-end", false),
    ]

    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    for (event, command, isAsync) in hookEntries {
        var hookDef: [String: Any] = ["type": "command", "command": command]
        if isAsync { hookDef["async"] = true }
        hooks[event] = [["matcher": "", "hooks": [hookDef]]]
    }
    settings["hooks"] = hooks

    guard let data = try? JSONSerialization.data(
        withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
          let json = String(data: data, encoding: .utf8)
    else { return 1 }

    try? json.write(toFile: path, atomically: true, encoding: .utf8)
    print("Updated \(path)")

    // Check for terminal-notifier
    let hasIt = !shell("which terminal-notifier").isEmpty
    if !hasIt {
        print("Warning: terminal-notifier not found. Install for click actions:")
        print("  brew install terminal-notifier")
        print("Notifications will still show but clicks won't focus the terminal.")
    }

    return 0
}

func uninstallHooks() -> Int32 {
    // Clean temp files
    let fm = FileManager.default
    if let files = try? fm.contentsOfDirectory(atPath: "/tmp") {
        for file in files where file.hasPrefix("claude-timer-") || file.hasPrefix("claude-notifier-") {
            try? fm.removeItem(atPath: "/tmp/\(file)")
        }
    }

    // Remove hooks from settings.json
    let path = settingsPath()
    guard let data = fm.contents(atPath: path),
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

    if let data = try? JSONSerialization.data(
        withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    print("Uninstalled")
    return 0
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: notifications <on-submit|notify|focus|on-end|install|uninstall>\n", stderr)
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
case "focus":
    // Direct focus by session ID
    if let timer = timerRead(args.count > 2 ? args[2] : ""),
       timer.count >= 4 {
        focusTerminal(
            terminal: timer[2], cwd: timer[1],
            tty: timer.count > 4 ? timer[4] : "",
            terminalId: timer.count > 5 ? timer[5] : "")
    }
    code = 0
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
