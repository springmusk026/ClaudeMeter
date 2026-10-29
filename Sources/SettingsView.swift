import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @State private var newAccount = ""
    @State private var commandsInstalled = Accounts.shellCommandsInstalled
    @AppStorage("menuLabel") private var labelMode = LabelMode.limit
    @AppStorage("metric") private var metric = Metric.cost
    @AppStorage("dailyBudget") private var budget = 0.0
    @AppStorage("budgetAlerts") private var budgetAlerts = false
    @AppStorage("resetAlerts") private var resetAlerts = false
    @AppStorage("limitAlerts") private var limitAlerts = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Picker("Menu bar shows", selection: $labelMode) {
                    ForEach(LabelMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Chart measures", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                TextField("Daily budget", value: $budget, format: .currency(code: "USD"))
                Toggle("Notify at 80% and 100% of budget", isOn: $budgetAlerts)
                    .disabled(budget <= 0)
            } header: {
                Text("Budget")
            } footer: {
                Text("Set to $0 to turn the budget off. When you go over it, the menu bar icon changes to a warning sign.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify at 80% and 95% of plan limits", isOn: $limitAlerts)
                Toggle("Notify when the 5-hour window resets", isOn: $resetAlerts)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Plan limits come from Claude Code through your status line script (~/.claude/statusline.sh). They're reported for subscription plans while a session is running.")
                    .foregroundStyle(.secondary)
            }

            accountsSection

            Section {
                LabeledContent("Version", value: version)
            } header: {
                Text("About")
            } footer: {
                Text("Costs are estimates at Anthropic API list prices. Subscription plans aren't billed per token. ClaudeMeter reads local files only and makes no network requests.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: budgetAlerts) { _, on in if on { Alerts.requestPermission() } }
        .onChange(of: resetAlerts) { _, on in if on { Alerts.requestPermission() } }
        .onChange(of: limitAlerts) { _, on in if on { Alerts.requestPermission() } }
        .onChange(of: launchAtLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(store.accounts) { account in
                let profile = store.profile(account.id)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: Binding(
                            get: { account.name },
                            set: { store.rename(account.id, to: $0) }))
                            .labelsHidden()
                            .frame(maxWidth: 170)
                        Text(profile.signedIn
                             ? [profile.email, profile.plan].compactMap { $0 }.joined(separator: " · ")
                             : "Not signed in · \(account.displayPath)")
                            .font(.caption)
                            .foregroundStyle(profile.signedIn ? Color.secondary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(profile.signedIn ? "Open" : "Sign In") { Accounts.launch(account) }
                        .help(profile.signedIn ? "Open Claude Code with this account in Terminal"
                                               : "Opens Claude Code for this account. Run /login there.")
                    Button { NSWorkspace.shared.open(account.dir) } label: { Image(systemName: "folder") }
                        .help("Show folder in Finder")
                    if !account.isDefault {
                        Button { store.remove(account.id) } label: { Image(systemName: "minus.circle") }
                            .help("Stop tracking this account. Its folder and login stay on this Mac.")
                    }
                }
                .buttonStyle(.borderless)
            }
            HStack {
                TextField("New account name", text: $newAccount)
                    .onSubmit(addAccount)
                Button("Add Account", action: addAccount)
                    .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if store.multiAccount {
                Picker("New sessions use", selection: Binding(get: { store.activeID }, set: { store.setActive($0) })) {
                    ForEach(store.accounts) { Text($0.name).tag($0.id) }
                }
                LabeledContent("Terminal commands") {
                    if commandsInstalled {
                        Text((["claude (follows the selection)"] + store.accounts.filter { !$0.isDefault }.map(\.command))
                                .joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Button("Install") {
                            Accounts.installShellCommands()
                            commandsInstalled = Accounts.shellCommandsInstalled
                        }
                        .help("Adds one line to ~/.zshrc: `claude` then starts the selected account, and commands like claude-work start a specific one, in any folder")
                    }
                }
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Each account keeps its own login in its own folder, using Claude Code's CLAUDE_CONFIG_DIR setting. Open a new account once and run /login to sign in. Switching is manual: ClaudeMeter never moves your logins or picks an account for you.")
                .foregroundStyle(.secondary)
        }
    }

    private func addAccount() {
        store.addAccount(named: newAccount)
        newAccount = ""
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
