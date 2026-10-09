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

enum Links { static let repo = URL(string: "https://github.com/tschannik/claude-account-router")! }

@MainActor
func showAbout() {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let credits = NSMutableAttributedString(
        string: "Run several Claude desktop accounts side by side, and send every claude:// link to the right one.\n\nUnofficial, not affiliated with Anthropic.\n",
        attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para, .foregroundColor: NSColor.labelColor])
    credits.append(NSAttributedString(string: "github.com/tschannik/claude-account-router",
        attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para, .link: Links.repo]))
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

/// "Accounts" menu: start or show each account with ⌘1...⌘9, and the link-routing switch.
struct AccountCommands: Commands {
    @ObservedObject var m = Manager.shared
    var body: some Commands {
        CommandMenu("Accounts") {
            ForEach(Array(m.accounts.prefix(9).enumerated()), id: \.element.id) { i, a in
                Button((m.running[a.name] != nil ? "Show " : "Start ") + a.name) { m.startReportingErrors(a) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
            if !m.accounts.isEmpty { Divider() }
            Toggle("Ask Which Account for Links", isOn: Binding(get: { m.routingOn }, set: { m.setRouting($0) }))
        }
    }
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
            CommandGroup(replacing: .appInfo) {
                Button("About Claude Accounts") { showAbout() }
                Button("Check for Updates…") { Updates.shared.checkNow() }.disabled(!Updates.shared.enabled)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Account…") { Manager.shared.showAdd = true }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            AccountCommands()
            CommandGroup(replacing: .help) {
                Link("Claude Accounts on GitHub", destination: Links.repo)
                Link("Release Notes", destination: Links.repo.appendingPathComponent("releases"))
                Link("Report an Issue…", destination: Links.repo.appendingPathComponent("issues/new"))
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
                _ = NSApplication.shared
                exit(args.count > 2 && MainActor.assumeIsolated({ writeAppIcon(to: args[2]) }) ? 0 : 1)
            case "--render-readme-assets": // docs build: ClaudeAccounts --render-readme-assets <dir>
                _ = NSApplication.shared
                exit(args.count > 2 && MainActor.assumeIsolated({ renderReadmeAssets(to: args[2]) }) ? 0 : 1)
            case "--render-dmg-background": // build-time: ClaudeAccounts --render-dmg-background <dir>
                _ = NSApplication.shared
                exit(args.count > 2 && MainActor.assumeIsolated({ renderDmgBackground(to: args[2]) }) ? 0 : 1)
            default: break
            }
        }
        ClaudeAccountsApp.main()
    }
}
