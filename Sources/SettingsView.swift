import SwiftUI
import ServiceManagement
import UserNotifications

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, limits, accounts, about
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general:  return "gearshape"
        case .limits:   return "gauge.with.dots.needle.67percent"
        case .accounts: return "person.2"
        case .about:    return "info.circle"
        }
    }
}

/// Settings: one toolbar tab per topic, each page built from the panel's cards.
struct SettingsView: View {
    var previewTab: SettingsTab? = nil   // set when rendering snapshots
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        if let previewTab {
            page(previewTab)
        } else {
            TabView(selection: $tab) {
                ForEach(SettingsTab.allCases) { t in
                    page(t).tabItem { Label(t.title, systemImage: t.icon) }.tag(t)
                }
            }
        }
    }

    @ViewBuilder private func page(_ t: SettingsTab) -> some View {
        Group {
            switch t {
            case .general:  GeneralSettings()
            case .limits:   LimitSettings()
            case .accounts: AccountSettings()
            case .about:    AboutSettings()
            }
        }
        .padding(Space.l)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var store: UsageStore
    @AppStorage("menuLabel") private var labelMode = LabelMode.limit
    @AppStorage("weeklyInIcon") private var weeklyInIcon = true
    @AppStorage("dailyBudget") private var budget = 0.0
    @AppStorage("budgetAlerts") private var budgetAlerts = false
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Card {
                SectionTitle("Menu bar", detail: "What sits next to the ring")
                VStack(spacing: 2) {
                    ForEach(LabelMode.allCases) { mode in
                        ModeRow(mode: mode, selected: mode == labelMode, preview: preview(mode)) {
                            withAnimation(Motion.quick) { labelMode = mode }
                        }
                    }
                }
                Hairline()
                SettingRow("Weekly limit as an inner ring") {
                    Toggle("", isOn: $weeklyInIcon).labelsHidden()
                }
            }

            budgetCard

            Card {
                SettingRow("Launch at login", detail: loginDetail, detailTint: loginStatus == .requiresApproval ? .caution : nil) {
                    if loginStatus == .requiresApproval {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Toggle("", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                             set: setLaunchAtLogin))
                        .labelsHidden()
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var budgetCard: some View {
        let today = store.snap(UsageStore.all).today.cost
        let share = budget > 0 ? today / budget : 0
        return Card {
            SectionTitle("Daily budget", detail: "Estimated at API list prices")
            SettingRow("Spend limit per day") {
                TextField("", value: $budget, format: .currency(code: "USD"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
            }
            if budget > 0 {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    DotTrack(value: share, tint: share >= 1 ? .critical : share >= 0.8 ? .caution : .claude, dots: 40)
                    HStack {
                        Text("\(fmtCost(today)) of \(fmtCost(budget)) today")
                        Spacer()
                        Text(share >= 1 ? "Over budget" : "\(fmtCost(max(0, budget - today))) left")
                            .foregroundStyle(share >= 1 ? Color.critical : Color.secondary)
                    }
                    .font(Typo.mono)
                    .foregroundStyle(.secondary)
                }
                Hairline()
                SettingRow("Notify at 80% and 100%") {
                    Toggle("", isOn: $budgetAlerts).labelsHidden()
                }
            } else {
                Text("Off. Set an amount to track spend; going over turns the menu bar icon red.")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: budgetAlerts) { _, on in if on { Alerts.requestPermission() } }
    }

    private func preview(_ mode: LabelMode) -> MenuBarContent {
        MenuBarLabel(all: store.snap(UsageStore.all),
                     current: store.snap(store.currentAccount.id),
                     currentName: store.multiAccount ? store.currentAccount.name : nil,
                     state: store.state(), mode: mode, budget: budget, showWeekly: weeklyInIcon).content
    }

    private var loginDetail: String? {
        loginStatus == .requiresApproval ? "Waiting for your approval in System Settings" : nil
    }

    private func setLaunchAtLogin(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        loginStatus = SMAppService.mainApp.status
    }
}

/// One menu bar option: a radio, its name, and the label it would draw, using live data.
private struct ModeRow: View {
    let mode: LabelMode
    let selected: Bool
    let preview: MenuBarContent
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Radio(on: selected)
                Text(mode.title).font(Typo.body)
                Spacer()
                preview
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .padding(.horizontal, Space.xs)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(scheme == .dark ? Color(white: 0.2) : Color(white: 0.9)))
                    .opacity(selected ? 1 : 0.55)
            }
            .padding(.horizontal, Space.xs)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(selected ? Color.selection : hovering ? Color.surface : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Limits

private struct LimitSettings: View {
    @EnvironmentObject var store: UsageStore
    @AppStorage("warnAt") private var warnAt = 80.0
    @AppStorage("criticalAt") private var criticalAt = 95.0
    @AppStorage("probeLimits") private var probeLimits = true
    @AppStorage("limitAlerts") private var limitAlerts = true
    @AppStorage("resetAlerts") private var resetAlerts = false
    @State private var permission: UNAuthorizationStatus?
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Card(glow: .claude, glowAt: .topTrailing) {
                SectionTitle("Levels", detail: "Colors, alerts and the status line change here")
                LevelBar(warn: warnAt, critical: criticalAt)
                    .animation(Motion.spring, value: warnAt)
                    .animation(Motion.spring, value: criticalAt)
                HStack(spacing: Space.s) {
                    LevelStepper(title: "Warning", tint: .caution, value: $warnAt, range: 50...90)
                    LevelStepper(title: "Critical", tint: .critical, value: $criticalAt, range: (warnAt + 5)...100)
                }
            }

            Card {
                SettingRow("Check limits every 5 minutes",
                           detail: "Uses Claude Code's local /usage: free, no model request") {
                    Toggle("", isOn: $probeLimits).labelsHidden()
                }
                Hairline()
                checkState
            }

            Card {
                SectionTitle("Notifications")
                if permission == .denied {
                    HStack(spacing: Space.xs) {
                        StatusDot(color: .caution)
                        Text("Notifications are turned off for ClaudeMeter").font(Typo.caption)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
                SettingRow("At your warning and critical levels") {
                    Toggle("", isOn: $limitAlerts).labelsHidden()
                }
                SettingRow("When a 5-hour window resets") {
                    Toggle("", isOn: $resetAlerts).labelsHidden()
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .task {
            guard !isSnapshot else { return }
            permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
        .onChange(of: limitAlerts) { _, on in if on { Alerts.requestPermission() } }
        .onChange(of: resetAlerts) { _, on in if on { Alerts.requestPermission() } }
        .onChange(of: probeLimits) { _, on in if on { store.probeLimits(force: true) } }
        .onChange(of: warnAt) { _, warn in if criticalAt <= warn { criticalAt = min(100, warn + 5) } }
    }

    /// Whether checks are working right now.
    @ViewBuilder private var checkState: some View {
        let signedIn = store.accounts.filter { store.profile($0.id).signedIn }.count
        HStack(spacing: Space.xs) {
            if !probeLimits {
                StatusDot(color: .secondary, hollow: true)
                Text("Off. Limits update only while a Claude Code session runs.")
            } else if store.probeFailures > 0 {
                StatusDot(color: .critical)
                Text("Couldn't read limits for \(store.probeFailures) of \(signedIn) \(signedIn == 1 ? "account" : "accounts")")
            } else if let last = store.lastProbe {
                StatusDot(color: .live)
                Text("Checked \(ago(last)) · \(signedIn) \(signedIn == 1 ? "account" : "accounts")")
            } else if signedIn == 0 {
                StatusDot(color: .caution)
                Text("No signed-in accounts to check")
            } else {
                StatusDot(color: .secondary, hollow: true)
                Text("Not checked yet")
            }
            Spacer()
            if probeLimits && signedIn > 0 {
                Button("Check Now") { store.probeLimits(force: true) }
            }
        }
        .font(Typo.caption)
        .foregroundStyle(.secondary)
    }

    private func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        return s < 60 ? "just now" : "\(fmtDuration(s)) ago"
    }
}

/// 0–100% as dots colored by level: normal, warning, critical.
private struct LevelBar: View {
    let warn: Double
    let critical: Double
    private let dots = 40

    var body: some View {
        Canvas { ctx, size in
            let d: CGFloat = 5
            let gap = (size.width - CGFloat(dots) * d) / CGFloat(dots - 1)
            for i in 0..<dots {
                let percent = (Double(i) + 0.5) / Double(dots) * 100
                let color: Color = percent >= critical ? .critical : percent >= warn ? .caution : .claude
                let rect = CGRect(x: CGFloat(i) * (d + gap), y: (size.height - d) / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(percent >= warn ? 1 : 0.45)))
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Warning at \(Int(warn)) percent, critical at \(Int(critical)) percent")
    }
}

/// A threshold with − and + in 5% steps.
private struct LevelStepper: View {
    let title: String
    let tint: Color
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: Space.xxs) {
            Circle().fill(tint).frame(width: 7, height: 7).padding(.trailing, Space.xxs)
            Text(title).font(Typo.body).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            step("minus", by: -5)
            Text("\(Int(value))%")
                .font(Typo.metric)
                .frame(width: 42)
                .contentTransition(.numericText(value: value))
            step("plus", by: 5)
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xxs)
        .frame(height: 36)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
    }

    private func step(_ icon: String, by delta: Double) -> some View {
        let next = value + delta
        return Button {
            withAnimation(Motion.quick) { value = next }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.selection))
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!range.contains(next))
        .opacity(range.contains(next) ? 1 : 0.35)
        .accessibilityLabel("\(delta > 0 ? "Raise" : "Lower") \(title.lowercased()) level")
    }
}

// MARK: - Accounts

private struct AccountSettings: View {
    @EnvironmentObject var store: UsageStore
    @State private var newAccount = ""
    @State private var commandsInstalled = Accounts.shellCommandsInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if store.multiAccount {
                Text("Choose the account new `claude` sessions use. Switching is manual and never touches your logins.")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            ForEach(store.accounts) { account in
                AccountRow(account: account,
                           profile: store.profile(account.id),
                           selectable: store.multiAccount,
                           selected: account.id == store.activeID,
                           working: isWorking(account))
            }

            Card {
                HStack(spacing: Space.xs) {
                    TextField("New account name, e.g. Work", text: $newAccount)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add Account", action: add)
                        .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Each account signs in once in its own folder: open it and run /login.")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }

            if store.multiAccount { commandsCard }
        }
    }

    private var commandsCard: some View {
        Card {
            HStack(spacing: Space.xs) {
                StatusDot(color: commandsInstalled ? .live : .secondary, hollow: !commandsInstalled)
                Text("Terminal commands").font(Typo.body)
                Spacer()
                if !commandsInstalled {
                    Button("Install") {
                        Accounts.installShellCommands()
                        commandsInstalled = Accounts.shellCommandsInstalled
                    }
                    .help("Adds one line to ~/.zshrc")
                }
            }
            if commandsInstalled {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    command("claude", "the selected account")
                    ForEach(store.accounts.filter { !$0.isDefault }) { command($0.command, $0.name) }
                }
            } else {
                Text("Makes `claude` follow your selection in any terminal, and adds a command per account.")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func command(_ name: String, _ meaning: String) -> some View {
        HStack(spacing: Space.xs) {
            Text(name).font(Typo.mono).textSelection(.enabled)
            Text(meaning).font(Typo.caption).foregroundStyle(.secondary)
        }
    }

    private func isWorking(_ account: Account) -> Bool {
        store.snap(account.id).live.sessions.contains { Activity(last: $0.lastActivity, now: Date()) == .working }
    }

    private func add() {
        store.addAccount(named: newAccount)
        newAccount = ""
    }
}

private struct AccountRow: View {
    @EnvironmentObject var store: UsageStore
    let account: Account
    let profile: AccountProfile
    let selectable: Bool
    let selected: Bool
    let working: Bool

    var body: some View {
        Card(outline: selectable && selected ? Color.claude.opacity(0.6) : nil) {
            HStack(spacing: Space.s) {
                if selectable {
                    Button { withAnimation(Motion.quick) { store.setActive(account.id) } } label: { Radio(on: selected) }
                        .buttonStyle(PressStyle())
                        .help("New sessions use \(account.name)")
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        TextField("Name", text: Binding(get: { account.name }, set: { store.rename(account.id, to: $0) }))
                            .textFieldStyle(.plain)
                            .font(Typo.title)
                            .fixedSize()
                        if working { StatusDot(color: .live, active: true).help("Working now") }
                        if selectable && selected { Badge(text: "New sessions", tint: .claude) }
                    }
                    Text(profile.signedIn ? [profile.email, profile.plan].compactMap { $0 }.joined(separator: " · ")
                                          : "Not signed in")
                        .font(Typo.caption)
                        .foregroundStyle(profile.signedIn ? Color.secondary : Color.caution)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if profile.signedIn {
                    CircleButton(icon: "terminal", help: "Open Claude Code with \(account.name)") { Accounts.launch(account) }
                } else {
                    Button("Sign In") { Accounts.launch(account) }
                        .help("Opens Claude Code for this account. Run /login there.")
                }
                CircleButton(icon: "folder", help: "Show \(account.displayPath) in Finder") { NSWorkspace.shared.open(account.dir) }
                if !account.isDefault {
                    CircleButton(icon: "minus", help: "Stop tracking. Its folder and login stay on this Mac.") {
                        store.remove(account.id)
                    }
                }
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @EnvironmentObject var store: UsageStore
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Card(glow: .claude) {
                HStack(spacing: Space.s) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ClaudeMeter").font(.system(size: 17, weight: .semibold))
                        Text("Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                            .font(Typo.mono).foregroundStyle(.secondary)
                        Text("Reads local files only. No network requests, no credentials.")
                            .font(Typo.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Card {
                SectionTitle("Setup")
                check("Claude Code", ok: Accounts.claudePath.hasPrefix("/"),
                      detail: Accounts.claudePath.hasPrefix("/") ? Accounts.claudePath.replacingOccurrences(of: Account.home.path, with: "~")
                                                                : "Not found in the usual places")
                check("Status line", ok: statusLineInstalled,
                      detail: statusLineInstalled ? "~/.claude/statusline.sh" : "Needed for live limits and context. See the README.")
                check("Terminal commands", ok: Accounts.shellCommandsInstalled,
                      detail: Accounts.shellCommandsInstalled ? "Installed in ~/.zshrc" : "Optional. Install from Accounts.",
                      optional: true)
            }

            Card {
                HStack(spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics").font(Typo.body)
                        Text("Versions, setup and data health for a bug report. No emails, account or project names.")
                            .font(Typo.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        store.copyDiagnostics()
                        withAnimation(Motion.quick) { copied = true }
                    }
                }
            }

            Text("Costs are estimates at Anthropic API list prices; subscription plans aren't billed per token.")
                .font(Typo.caption).foregroundStyle(.tertiary)
                .padding(.horizontal, Space.xxs)
        }
    }

    private func check(_ title: String, ok: Bool, detail: String, optional: Bool = false) -> some View {
        HStack(spacing: Space.xs) {
            StatusDot(color: ok ? .live : optional ? .secondary : .caution, hollow: !ok && optional)
            Text(title).font(Typo.body)
            Spacer()
            Text(detail).font(ok ? Typo.mono : Typo.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var statusLineInstalled: Bool {
        let settings = (try? String(contentsOf: Account.main.dir.appendingPathComponent("settings.json"), encoding: .utf8)) ?? ""
        return settings.contains("statusline.sh")
    }

    private func info(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
}

// MARK: - Pieces

private struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Typo.title)
            Spacer()
            if let detail { Text(detail).font(Typo.caption).foregroundStyle(.secondary) }
        }
    }
}

/// A setting's name (and optional explanation) with its control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var detailTint: Color? = nil
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, detailTint: Color? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.detail = detail; self.detailTint = detailTint; self.control = control()
    }

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body)
                if let detail {
                    Text(detail).font(Typo.caption).foregroundStyle(detailTint ?? .secondary)
                }
            }
            Spacer(minLength: Space.xs)
            control
        }
        .frame(minHeight: 24)
    }
}

private struct Radio: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.claude : Color.track, lineWidth: on ? 4.5 : 1)
            if on { Circle().fill(.white).frame(width: 5, height: 5) }
        }
        .frame(width: 14, height: 14)
    }
}

private struct Hairline: View {
    var body: some View { Rectangle().fill(Color.hairline).frame(height: 0.5) }
}
