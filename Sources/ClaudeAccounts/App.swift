import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            let m = Manager.shared
            for url in urls {
                switch url.scheme {
                case "claude": m.route(url)
                case "claudeaccounts": // claudeaccounts://launch/<name>, from the per-account launcher apps
                    if url.host == "launch", let a = m.accounts.first(where: { $0.name == url.lastPathComponent }) {
                        m.startReportingErrors(a)
                    }
                default: break
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ClaudeAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Claude Accounts", id: "main") {
            ContentView()
                .environmentObject(Manager.shared)
                .frame(width: 520)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.shared.checkNow() }.disabled(!Updates.shared.enabled)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.count > 1 {
            switch args[1] {
            case "--claim": // run by the LaunchAgent: idempotently put this app back as claude:// handler
                let id = Bundle.main.bundleIdentifier ?? "dev.yannik.claude-accounts"
                let cur = LSCopyDefaultHandlerForURLScheme("claude" as CFString)?.takeRetainedValue() as String?
                if cur != id {
                    log("claim: \(cur ?? "none") -> \(id)")
                    LSSetDefaultHandlerForURLScheme("claude" as CFString, id as CFString)
                }
                exit(0)
            case "--render-app-icon": // build-time: ClaudeAccounts --render-app-icon out.icns
                exit(args.count > 2 && writeAppIcon(to: args[2]) ? 0 : 1)
            case "--render-readme-assets": // docs build: ClaudeAccounts --render-readme-assets <dir>
                _ = NSApplication.shared
                exit(args.count > 2 && MainActor.assumeIsolated({ renderReadmeAssets(to: args[2]) }) ? 0 : 1)
            default: break
            }
        }
        ClaudeAccountsApp.main()
    }
}
