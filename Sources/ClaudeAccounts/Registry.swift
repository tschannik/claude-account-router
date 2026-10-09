import Foundation

/// One Claude desktop account: its own data folder and its own copy of Claude.app.
struct Account: Identifiable, Hashable {
    var name: String
    /// nil = Claude's default data folder
    var dataDir: String?
    var appPath: String
    var id: String { name }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let appSupport = home + "/Library/Application Support"
    // Same location the original shell tool used, so existing setups keep working.
    // CLAUDE_ACCOUNTS_ROOT lets tests and README screenshots use a throwaway registry.
    static let root = ProcessInfo.processInfo.environment["CLAUDE_ACCOUNTS_ROOT"] ?? appSupport + "/claude-accounts"
    static let registry = root + "/accounts.tsv"
    static let apps = root + "/apps"
    static let launchers = home + "/Applications/Claude Accounts"
    static let log = root + "/claude-accounts.log"
    static let agentLabel = "dev.yannik.claude-accounts.claim"
    static let agentPlist = home + "/Library/LaunchAgents/" + agentLabel + ".plist"
    static let launchServicesPrefs = home + "/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"

    static let claudeBundleID = "com.anthropic.claudefordesktop"

    /// The installed Claude.app every account copy is cloned from.
    static var sourceApp: String? {
        ["/Applications/Claude.app", home + "/Applications/Claude.app"]
            .first { FileManager.default.fileExists(atPath: $0 + "/Contents/Info.plist") }
    }
}

func log(_ message: String) {
    try? FileManager.default.createDirectory(atPath: Paths.root, withIntermediateDirectories: true)
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(message)\n"
    if let h = FileHandle(forWritingAtPath: Paths.log) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.write(toFile: Paths.log, atomically: true, encoding: .utf8)
    }
}

/// accounts.tsv: name <TAB> data dir ("-" = Claude default) <TAB> app path
enum Registry {
    static func load() -> [Account] {
        guard let text = try? String(contentsOfFile: Paths.registry, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, !f[0].isEmpty else { return nil }
            return Account(name: f[0], dataDir: f[1] == "-" ? nil : f[1], appPath: f[2])
        }
    }

    static func save(_ accounts: [Account]) {
        try? FileManager.default.createDirectory(atPath: Paths.root, withIntermediateDirectories: true)
        let text = accounts.map { "\($0.name)\t\($0.dataDir ?? "-")\t\($0.appPath)\n" }.joined()
        try? text.write(toFile: Paths.registry, atomically: true, encoding: .utf8)
    }

    static func validName(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$", options: .regularExpression) != nil
    }
}
