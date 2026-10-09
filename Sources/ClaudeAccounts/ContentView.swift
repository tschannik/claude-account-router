import Combine
import SwiftUI

struct BadgeView: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        let c = Color(nsColor: nsColor(badgeColorHex(name)))
        ZStack {
            Circle().fill(LinearGradient(colors: [c.opacity(0.85), c], startPoint: .top, endPoint: .bottom))
            Text(name.prefix(1).uppercased()).font(.system(size: size * 0.45, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: c.opacity(0.35), radius: 6, y: 2)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Manager
    @State private var showAdd = false
    @State private var newName = ""
    @State private var firstName = "personal"
    @State private var happyUntil = Date.distantPast
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            if Paths.sourceApp == nil {
                message("Claude.app not found", "Install Claude Desktop in /Applications first, then reopen this app.")
            } else if m.accounts.isEmpty {
                firstRun
            } else {
                ScrollView {
                    VStack(spacing: 10) { ForEach(m.accounts) { row($0) } }.padding(.horizontal, 20).padding(.bottom, 16)
                }
                .frame(height: CGFloat(min(m.accounts.count, 6)) * 80 + 6) // the window grows with the list
            }
            routingCard.padding(20).padding(.top, 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { m.refresh(); m.healAgentPath() }
        .onReceive(tick) { _ in m.refresh() }
        .onChange(of: m.running.count) { n in if n > 0 { cheer() } }
        .alert("Claude Accounts", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button("OK") { m.error = nil }
        } message: { Text(m.error ?? "") }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Mascot(happyUntil: happyUntil).onTapGesture { cheer() }
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Accounts").font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !m.accounts.isEmpty {
                Button { newName = ""; showAdd = true } label: { Label("Add account", systemImage: "plus") }
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 12)
    }

    private func cheer() { happyUntil = Date().addingTimeInterval(1.6) }

    private var subtitle: String {
        let n = m.accounts.count
        let up = m.running.count
        if n == 0 { return "Several Claude sign-ins, side by side" }
        return "\(n) account\(n == 1 ? "" : "s") · \(up) running" + (m.sourceVersion.map { " · Claude \($0)" } ?? "")
    }

    private func row(_ a: Account) -> some View {
        let isUp = m.running[a.name] != nil
        return Card {
            HStack(spacing: 14) {
                BadgeView(name: a.name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(isUp ? Color.green : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                            .shadow(color: isUp ? .green.opacity(0.6) : .clear, radius: 3)
                        Text(isUp ? "Running" : "Not running").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isUp {
                    Button("Show") { m.startReportingErrors(a) }.buttonStyle(.bordered).controlSize(.large)
                } else {
                    Button("Start") { m.startReportingErrors(a) }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                Menu {
                    Button(m.hasLauncher(a) ? "Recreate launcher" : "Create launcher in Applications") { m.makeLauncher(a) }
                    Button("Show data folder") {
                        let dir = a.dataDir ?? Paths.appSupport + "/Claude"
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dir)])
                    }
                    Divider()
                    Button("Remove account…", role: .destructive) { m.remove(a) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).frame(width: 26, height: 26) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    private var routingCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "link").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask which account for links").font(.system(size: 14, weight: .semibold))
                    Text(m.routingOn ? "claude:// links (sign-in, “open in app”) show an account chooser."
                                     : "Off: macOS sends claude:// links to whichever Claude it picks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { m.routingOn }, set: { m.setRouting($0) })).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity).frame(height: 220)
    }

    private var firstRun: some View {
        VStack(spacing: 16) {
            Spacer()
            Mascot(happyUntil: happyUntil, scale: 1.6).onTapGesture { cheer() }
            Text("Your current Claude sign-in becomes the first account.").font(.headline)
            Text("Add more afterwards; each one gets its own sign-in and its own copy of Claude.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            HStack {
                Text("Name it:")
                TextField("personal", text: $firstName).frame(width: 140)
            }
            Button("Get started") { m.addExistingLogin(named: firstName.trimmingCharacters(in: .whitespaces)) }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            Spacer()
        }.padding(.horizontal, 32).frame(maxWidth: .infinity).frame(height: 330)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New account").font(.title3.bold())
            Text("It gets its own copy of Claude and its own sign-in. Start it once from the list and sign in.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name, e.g. work", text: $newName).textFieldStyle(.roundedBorder).frame(width: 300)
            HStack {
                Spacer()
                Button("Cancel") { showAdd = false }.keyboardShortcut(.cancelAction)
                Button("Add") { m.add(named: newName.trimmingCharacters(in: .whitespaces)); showAdd = false }
                    .keyboardShortcut(.defaultAction).disabled(newName.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width: 340)
    }
}
