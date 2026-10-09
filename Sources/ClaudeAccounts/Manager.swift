import AppKit
import CoreServices

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@discardableResult
func run(_ exe: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

@MainActor
final class Manager: ObservableObject {
    static let shared = Manager()

    @Published var accounts: [Account] = Registry.load()
    @Published var running: [String: Int] = [:]
    @Published var handler: String = ""
    @Published var error: String?
    @Published var showAdd = false

    var selfID: String { Bundle.main.bundleIdentifier ?? "dev.yannik.claude-accounts" }
    var routingOn: Bool { handler == selfID }
    var sourceVersion: String? { Paths.sourceApp.flatMap(bundleVersion) }

    // MARK: process state

    private struct Proc { let pid: Int; let cmd: String }

    private func processes() -> [Proc] {
        run("/bin/ps", ["-axo", "pid=,command="]).out.split(separator: "\n").compactMap { line in
            let s = line.drop { $0 == " " }
            guard let sp = s.firstIndex(of: " "), let pid = Int(s[..<sp]) else { return nil }
            return Proc(pid: pid, cmd: String(s[s.index(after: sp)...]))
        }
    }

    /// Main (non-helper) Claude process of this account, found by app path + data dir.
    private func pid(of a: Account, in procs: [Proc]) -> Int? {
        let exe = a.appPath + "/Contents/MacOS/Claude"
        return procs.first { p in
            guard p.cmd.hasPrefix(exe), !p.cmd.contains("--type=") else { return false }
            let rest = p.cmd.dropFirst(exe.count)
            guard rest.isEmpty || rest.first == " " else { return false }
            if let dd = a.dataDir { return p.cmd.contains("--user-data-dir=" + dd) }
            return !p.cmd.contains("--user-data-dir=")
        }?.pid
    }

    /// Any Claude main process (whatever app path) using this data dir.
    private func dirUsers(_ dd: String) -> [Int] {
        processes().filter {
            $0.cmd.contains("/Contents/MacOS/Claude") && !$0.cmd.contains("--type=") && $0.cmd.contains("--user-data-dir=" + dd)
        }.map(\.pid)
    }

    func refresh() {
        let procs = processes()
        var r: [String: Int] = [:]
        for a in accounts { if let p = pid(of: a, in: procs) { r[a.name] = p } }
        // README screenshots only: CLAUDE_ACCOUNTS_DEMO_RUNNING=name1,name2 shows those accounts as running
        for n in (ProcessInfo.processInfo.environment["CLAUDE_ACCOUNTS_DEMO_RUNNING"] ?? "").split(separator: ",") { r[String(n)] = 1 }
        if r != running { running = r }
        let h = currentHandler()
        if h != handler { handler = h }
    }

    // MARK: copies of Claude.app

    func bundleVersion(_ app: String) -> String? {
        (NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleVersion"] as? String)
    }

    private func clone(_ a: Account) throws {
        guard let src = Paths.sourceApp else { throw AppError(message: "Claude.app was not found in /Applications.") }
        try FileManager.default.createDirectory(atPath: (a.appPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let tmp = a.appPath + ".new"
        try? FileManager.default.removeItem(atPath: tmp)
        // cp -c = APFS clone: instant, no extra disk, signature stays valid
        guard run("/bin/cp", ["-Rc", src, tmp]).status == 0 else { throw AppError(message: "Could not copy Claude.app.") }
        try? FileManager.default.removeItem(atPath: a.appPath)
        try FileManager.default.moveItem(atPath: tmp, toPath: a.appPath)
    }

    /// Makes sure the account has a copy; refreshes it when behind (never downgrades, never while running).
    func ensureCopy(_ a: Account) throws {
        guard let src = Paths.sourceApp, a.appPath != src else { return }
        guard FileManager.default.fileExists(atPath: a.appPath) else { log("clone for \(a.name)"); return try clone(a) }
        guard let cv = bundleVersion(a.appPath), let sv = bundleVersion(src),
              sv.compare(cv, options: .numeric) == .orderedDescending else { return }
        if running[a.name] != nil { log("refresh skipped: \(a.name) running"); return }
        log("refresh \(a.name): \(cv) -> \(sv)")
        try clone(a)
    }

    // MARK: starting accounts

    func start(_ a: Account) throws {
        refresh()
        if running[a.name] != nil { run("/usr/bin/open", ["-a", a.appPath]); return }
        if let dd = a.dataDir, let other = dirUsers(dd).first {
            throw AppError(message: "\(a.name) is already running through another launcher (pid \(other)). Quit it first, so one data folder is never opened twice.")
        }
        try ensureCopy(a)
        log("start \(a.name)")
        if let dd = a.dataDir { run("/usr/bin/open", ["-n", "-a", a.appPath, "--args", "--user-data-dir=" + dd]) }
        else { run("/usr/bin/open", ["-a", a.appPath]) }
    }

    func startReportingErrors(_ a: Account) {
        do { try start(a) } catch { self.error = error.localizedDescription }
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); refresh() }
    }

    /// Hands a claude:// link to the account's own copy (open -a <copy> reaches the instance running from that path).
    func deliver(_ url: URL, to a: Account) async {
        do {
            if pidNow(a) == nil {
                try start(a)
                var up = false
                for _ in 0..<60 { if pidNow(a) != nil { up = true; break }; try? await Task.sleep(nanoseconds: 500_000_000) }
                guard up else { error = "\(a.name) did not start."; return }
                try? await Task.sleep(nanoseconds: 4_000_000_000) // let the app finish booting before the link event
            }
            log("deliver to \(a.name): \(url.absoluteString)")
            run("/usr/bin/open", ["-a", a.appPath, url.absoluteString])
        } catch { self.error = error.localizedDescription }
        refresh()
    }

    private func pidNow(_ a: Account) -> Int? { pid(of: a, in: processes()) }

    // MARK: accounts

    private func accountsForNew(_ name: String) -> Account {
        Account(name: name, dataDir: Paths.appSupport + "/Claude-" + name, appPath: Paths.apps + "/" + name + "/Claude.app")
    }

    /// First account of a fresh setup: the user's existing Claude login (default data folder, original app).
    func addExistingLogin(named name: String) {
        guard let src = Paths.sourceApp else { error = "Claude.app was not found in /Applications."; return }
        guard Registry.validName(name), !accounts.contains(where: { $0.name == name }) else { error = "Pick a different name (letters, digits, - and _)."; return }
        accounts.append(Account(name: name, dataDir: nil, appPath: src))
        Registry.save(accounts); log("added \(name) (default login)")
    }

    func add(named name: String) {
        guard Registry.validName(name) else { error = "Names may use letters, digits, - and _ (max 31)."; return }
        guard !accounts.contains(where: { $0.name == name }) else { error = "'\(name)' already exists."; return }
        let a = accountsForNew(name)
        do { try ensureCopy(a) } catch { self.error = error.localizedDescription; return }
        accounts.append(a); Registry.save(accounts); log("added \(name)")
        makeLauncher(a)
    }

    /// Removes the account entry, its copy of Claude.app and its launcher. The data folder (the sign-in) is kept.
    func remove(_ a: Account) {
        refresh()
        guard running[a.name] == nil else { error = "Quit \(a.name) first."; return }
        if a.appPath != Paths.sourceApp { try? FileManager.default.removeItem(atPath: (a.appPath as NSString).deletingLastPathComponent) }
        try? FileManager.default.removeItem(atPath: launcherPath(a))
        accounts.removeAll { $0.name == a.name }
        Registry.save(accounts); log("removed \(a.name)")
    }

    // MARK: launchers (~/Applications/Claude Accounts/Claude <name>.app, open claudeaccounts://launch/<name>)

    func launcherPath(_ a: Account) -> String { Paths.launchers + "/Claude \(a.name).app" }
    func hasLauncher(_ a: Account) -> Bool { FileManager.default.fileExists(atPath: launcherPath(a)) }

    func makeLauncher(_ a: Account) {
        let app = launcherPath(a), fm = FileManager.default
        do {
            try? fm.removeItem(atPath: app)
            try fm.createDirectory(atPath: app + "/Contents/MacOS", withIntermediateDirectories: true)
            try fm.createDirectory(atPath: app + "/Contents/Resources", withIntermediateDirectories: true)
            let script = app + "/Contents/MacOS/launch"
            try "#!/bin/sh\nexec /usr/bin/open \"claudeaccounts://launch/\(a.name)\"\n".write(toFile: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
            let info: [String: Any] = [
                "CFBundleIdentifier": "dev.yannik.claude-account.\(a.name)", "CFBundleName": "Claude \(a.name)",
                "CFBundleExecutable": "launch", "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon",
                "CFBundleVersion": "1", "CFBundleShortVersionString": "1", "LSUIElement": true]
            try (info as NSDictionary).write(to: URL(fileURLWithPath: app + "/Contents/Info.plist"))
            if let src = Paths.sourceApp,
               let icon = (NSDictionary(contentsOfFile: src + "/Contents/Info.plist")?["CFBundleIconFile"] as? String) {
                let base = src + "/Contents/Resources/" + (icon.hasSuffix(".icns") ? icon : icon + ".icns")
                _ = writeBadgedIcon(base: base, to: app + "/Contents/Resources/AppIcon.icns", letter: a.name, rgb: badgeColorHex(a.name))
            }
            run("/usr/bin/codesign", ["--force", "--sign", "-", app])
            run("/usr/bin/touch", [app])
            objectWillChange.send()
        } catch { self.error = "Could not create the launcher: \(error.localizedDescription)" }
    }

    // MARK: claude:// link handling

    func currentHandler() -> String {
        LSCopyDefaultHandlerForURLScheme("claude" as CFString)?.takeRetainedValue() as String? ?? ""
    }

    /// Router on: this app owns claude:// and a small LaunchAgent re-claims it after Claude's startup re-registration.
    func setRouting(_ on: Bool) {
        let uid = String(getuid())
        retireLegacyAgent(uid)
        if on {
            let exe = Bundle.main.executablePath ?? ""
            let plist: [String: Any] = [
                "Label": Paths.agentLabel, "ProgramArguments": [exe, "--claim"],
                "WatchPaths": [Paths.launchServicesPrefs], "ThrottleInterval": 5]
            try? FileManager.default.createDirectory(atPath: (Paths.agentPlist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            (plist as NSDictionary).write(toFile: Paths.agentPlist, atomically: true)
            LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
            LSSetDefaultHandlerForURLScheme("claude" as CFString, selfID as CFString)
            run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Paths.agentLabel)"])
            run("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.agentPlist])
            log("routing on")
        } else {
            run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Paths.agentLabel)"])
            try? FileManager.default.removeItem(atPath: Paths.agentPlist)
            LSSetDefaultHandlerForURLScheme("claude" as CFString, Paths.claudeBundleID as CFString)
            log("routing off")
        }
        refresh()
    }

    /// The first version of this tool (shell script + router applet) had its own re-claim agent; never run both.
    private func retireLegacyAgent(_ uid: String) {
        let label = "dev.yannik.claude-link-claim"
        let plist = Paths.home + "/Library/LaunchAgents/" + label + ".plist"
        guard FileManager.default.fileExists(atPath: plist) else { return }
        run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(atPath: plist)
        log("retired legacy agent")
    }

    /// The agent re-points the existing plist when the app was moved, so it never runs a stale path.
    func healAgentPath() {
        guard let d = NSDictionary(contentsOfFile: Paths.agentPlist), let exe = Bundle.main.executablePath,
              (d["ProgramArguments"] as? [String])?.first != exe else { return }
        setRouting(true)
    }

    // MARK: "which account?" chooser for claude:// links

    func route(_ url: URL) {
        guard url.scheme == "claude" else { return }
        guard !accounts.isEmpty else { error = "Add an account first."; NSApp.activate(ignoringOtherApps: true); return }
        let alert = NSAlert()
        alert.messageText = "Open this link in which account?"
        alert.informativeText = url.absoluteString
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        popup.addItems(withTitles: accounts.map(\.name))
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, let a = accounts.first(where: { $0.name == popup.titleOfSelectedItem }) else { return }
        Task { await deliver(url, to: a) }
    }
}
