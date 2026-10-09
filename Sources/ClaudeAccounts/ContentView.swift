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

/// Speech bubble with a small tail on the left, pointing at the mascot.
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tail: CGFloat = 8
        p.addRoundedRect(in: CGRect(x: r.minX + tail, y: r.minY, width: r.width - tail, height: r.height), cornerSize: CGSize(width: 12, height: 12))
        p.move(to: CGPoint(x: r.minX + tail + 1, y: r.midY - 6))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + 2))
        p.addLine(to: CGPoint(x: r.minX + tail + 1, y: r.midY + 8))
        p.closeSubpath()
        return p
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Manager
    @ObservedObject private var updates = Updates.shared
    @State private var newName = ""
    @State private var firstName = "personal"
    @State private var pulse = false
    @State private var happyUntil = Date.distantPast
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if Paths.sourceApp == nil {
                message("Claude.app not found", "Install Claude Desktop in /Applications first, then reopen this app.")
            } else if m.accounts.isEmpty {
                firstRun
            } else {
                mascotRow
                if let link = m.pendingLink { linkCard(link).padding(.horizontal, 20).padding(.bottom, 10) }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(m.accounts) { row($0) }
                        ForEach(m.importable(), id: \.dir) { importCard($0) }
                            .opacity(m.pendingLink != nil ? 0.35 : 1).disabled(m.pendingLink != nil)
                    }.padding(.horizontal, 20).padding(.vertical, 2)
                }
                .frame(height: listHeight)
                SectionLabel("Links").padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
                routingCard.padding(.horizontal, 20).padding(.bottom, 20)
                    .opacity(m.pendingLink != nil ? 0.35 : 1).disabled(m.pendingLink != nil)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { m.refresh(); m.healAgentPath() }
        .onReceive(tick) { _ in m.refresh() }
        .onChange(of: m.running.count) { n in if n > 0 { cheer() } }
        .onReceive(Updates.shared.$found) { if $0 > Date() { happyUntil = $0 } }
        .alert("Claude Accounts", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button("OK") { m.error = nil }
        } message: { Text(m.error ?? "") }
        .sheet(isPresented: $m.showAdd) { addSheet }
    }

    private var listHeight: CGFloat { CGFloat(min(m.accounts.count + m.importable().count, 6)) * 80 + 6 }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Claude Accounts").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !m.accounts.isEmpty {
                Button { newName = ""; m.showAdd = true } label: { Label("Add account", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(m.pendingLink != nil)
            }
        }
        .opacity(m.pendingLink != nil ? 0.5 : 1)
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 6)
    }

    private var subtitle: String {
        let n = m.accounts.count
        if n == 0 { return "Several Claude sign-ins, side by side" }
        return "\(n) account\(n == 1 ? "" : "s")" + (m.sourceVersion.map { " · Claude \($0)" } ?? "")
    }

    /// The mascot stands on the edge of the account list and comments on what is going on.
    private var mascotRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Mascot(happyUntil: happyUntil).onTapGesture { cheer() }
            Text(bubbleText)
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 8)
                .background(BubbleShape().fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(BubbleShape().stroke(Color.primary.opacity(0.08)))
                .padding(.bottom, 14)
                .animation(.easeInOut(duration: 0.2), value: bubbleText)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.bottom, -7).zIndex(1)
    }

    private var bubbleText: String {
        let n = m.accounts.count, up = m.running.count
        if m.pendingLink != nil { return "Which account should open this link?" }
        if updates.available { return "A new version is ready. See the app menu." }
        if up == 0 { return "Hi! Pick an account to start." }
        if up == n { return n == 1 ? "All set, it's running." : "All \(n) running." }
        return "\(up) of \(n) running."
    }

    private func row(_ a: Account) -> some View {
        let isUp = m.running[a.name] != nil
        return Card {
            HStack(spacing: 14) {
                BadgeView(name: a.name)
                VStack(alignment: .leading, spacing: 5) {
                    Text(a.name).font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(isUp ? Color.green : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
                        Text(isUp ? "Running" : "Not running").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isUp ? Color.green : Color.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(isUp ? Color.green.opacity(0.13) : Color.primary.opacity(0.06)))
                }
                Spacer()
                if m.pendingLink != nil {
                    Button("Open link") { m.openPendingLink(in: a) }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button(isUp ? "Show" : "Start") { m.startReportingErrors(a) }
                        .buttonStyle(.bordered).controlSize(.large).foregroundStyle(isUp ? Color.primary : Color.accentColor)
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
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2).opacity(m.pendingLink != nil ? 1 : 0))
    }

    private func importCard(_ f: (name: String, dir: String)) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found “Claude-\(f.name)”").font(.system(size: 14, weight: .semibold))
                    Text("An earlier Claude sign-in on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Not now") { m.dismissImport(dir: f.dir) }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                Button("Add as “\(f.name)”") { m.addImported(name: f.name, dir: f.dir) }.buttonStyle(.bordered)
            }
        }
    }

    /// Unmissable call to action: filled accent banner with a pulsing ring, while the rest of the window steps back.
    private func linkCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: 2).frame(width: 34, height: 34)
                        .scaleEffect(pulse ? 1.35 : 1).opacity(pulse ? 0 : 0.9)
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose an account below").font(.system(size: 16, weight: .bold))
                    Text("A claude:// link is waiting for you.").font(.callout).opacity(0.9)
                }
                Spacer()
                Button("Cancel") { m.pendingLink = nil }.buttonStyle(.bordered).tint(.white).keyboardShortcut(.cancelAction)
            }
            Text(url.absoluteString).font(.system(size: 11, design: .monospaced))
                .lineLimit(1).truncationMode(.middle).help(url.absoluteString)
                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18)))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.gradient))
        .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 3)
        .onAppear { withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true } }
        .onDisappear { pulse = false }
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

    private func cheer() { happyUntil = Date().addingTimeInterval(1.6) }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity).frame(height: 220)
    }

    private var firstRun: some View {
        VStack(spacing: 16) {
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
        }.padding(.horizontal, 32).padding(.vertical, 20).frame(maxWidth: .infinity)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New account").font(.title3.bold())
            Text("It gets its own copy of Claude and its own sign-in. Start it once from the list and sign in.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name, e.g. work", text: $newName).textFieldStyle(.roundedBorder).frame(width: 300)
            HStack {
                Spacer()
                Button("Cancel") { m.showAdd = false }.keyboardShortcut(.cancelAction)
                Button("Add") { m.add(named: newName.trimmingCharacters(in: .whitespaces)); m.showAdd = false }
                    .keyboardShortcut(.defaultAction).disabled(newName.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width: 340)
    }
}
