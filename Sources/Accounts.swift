import AppKit

/// A Claude account. Each one has its own Claude Code config folder, selected
/// with Claude Code's CLAUDE_CONFIG_DIR setting; Claude Code keeps that account's
/// login itself. ClaudeMeter never reads or moves credentials.
struct Account: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var path: String

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let main = Account(id: "default", name: "Default", path: home.appendingPathComponent(".claude").path)

    var isDefault: Bool { id == Account.main.id }
    var dir: URL { URL(fileURLWithPath: path) }
    var projects: URL { dir.appendingPathComponent("projects") }
    var liveDir: URL { dir.appendingPathComponent("claudemeter/live") }
    var summaryFile: URL { dir.appendingPathComponent("claudemeter.json") }
    var displayPath: String { path.replacingOccurrences(of: Account.home.path, with: "~") }
    var command: String { isDefault ? "claude" : "claude-\(id)" }
}

enum Accounts {
    // MARK: Storage

    static func load() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: "accounts"),
              let saved = try? JSONDecoder().decode([Account].self, from: data), !saved.isEmpty
        else { return [.main] }
        return saved.contains { $0.isDefault } ? saved : [.main] + saved
    }

    static func save(_ accounts: [Account]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: "accounts")
        writeShellCommands(accounts)
    }

    /// A short, unique, shell-safe id from a display name: "Work Account" -> "work-account"
    static func makeID(_ name: String, taken: Set<String>) -> String {
        let cleaned = name.lowercased().unicodeScalars
            .map { $0.isASCII && CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
        let base = cleaned.split(separator: "-").joined(separator: "-")
        let stem = base.isEmpty ? "account" : base
        var id = stem
        var n = 2
        while taken.contains(id) || id == Account.main.id {
            id = "\(stem)-\(n)"
            n += 1
        }
        return id
    }

    // MARK: Setup

    /// Creates the account's folders. A new account starts with the default
    /// account's settings plus the shared status line, which reports its limits.
    static func prepare(_ account: Account) {
        let fm = FileManager.default
        try? fm.createDirectory(at: account.liveDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: account.projects, withIntermediateDirectories: true)

        let settings = account.dir.appendingPathComponent("settings.json")
        guard !account.isDefault, !fm.fileExists(atPath: settings.path) else { return }
        var obj = (try? Data(contentsOf: Account.main.dir.appendingPathComponent("settings.json")))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        obj["statusLine"] = ["type": "command", "command": "~/.claude/statusline.sh", "padding": 0]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settings)
        }
    }

    // MARK: Launching

    /// Opens Terminal running Claude Code signed in to `account`.
    static func launch(_ account: Account) {
        let dir = Account.home.appendingPathComponent("Library/Application Support/ClaudeMeter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("\(account.id).command")

        var lines = ["#!/bin/zsh -l", "cd ~"]
        if !account.isDefault { lines.append("export CLAUDE_CONFIG_DIR=\(shellQuote(account.path))") }
        lines.append("echo \(shellQuote("Claude Code · \(account.name)"))")
        lines.append("exec \(shellQuote(claudePath))")
        try? (lines.joined(separator: "\n") + "\n").write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }

    private static var claudePath: String {
        let candidates = [Account.home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    // MARK: Terminal commands

    /// One shell function per extra account, e.g. `claude-work`, usable in any folder.
    static let shellFile = Account.main.dir.appendingPathComponent("claudemeter/accounts.zsh")
    private static let zshrc = Account.home.appendingPathComponent(".zshrc")
    private static let sourceLine =
        "[ -f ~/.claude/claudemeter/accounts.zsh ] && source ~/.claude/claudemeter/accounts.zsh  # ClaudeMeter accounts"

    static var shellCommandsInstalled: Bool {
        (try? String(contentsOf: zshrc, encoding: .utf8))?.contains("claudemeter/accounts.zsh") ?? false
    }

    static func writeShellCommands(_ accounts: [Account]) {
        var lines = [
            "# Generated by ClaudeMeter.",
            "",
            "# `claude` starts the account selected in ClaudeMeter, unless CLAUDE_CONFIG_DIR is already set.",
            "claude() {",
            "  local dir=''",
            "  [[ -f ~/.claude/claudemeter/active-account ]] && dir=$(<~/.claude/claudemeter/active-account)",
            "  if [[ -n $dir && -z $CLAUDE_CONFIG_DIR ]]; then CLAUDE_CONFIG_DIR=$dir command claude \"$@\"; else command claude \"$@\"; fi",
            "}",
            "",
            "# One command per extra account, e.g. claude-work.",
        ]
        for a in accounts where !a.isDefault {
            lines.append("\(a.command)() { CLAUDE_CONFIG_DIR=\(shellQuote(a.path)) command claude \"$@\" }")
        }
        try? FileManager.default.createDirectory(at: shellFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: shellFile, atomically: true, encoding: .utf8)
    }

    /// Adds one line to ~/.zshrc that loads the generated commands.
    static func installShellCommands() {
        guard !shellCommandsInstalled else { return }
        let existing = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
        let text = existing + (existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n") + sourceLine + "\n"
        try? text.write(to: zshrc, atomically: true, encoding: .utf8)
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Profile (who is signed in)

/// The signed-in user and plan, from the account's Claude Code profile
/// (`oauthAccount` in .claude.json). No tokens: those stay in the Keychain.
struct AccountProfile {
    var email: String?
    var plan: String?
    var signedIn: Bool { email != nil }
}

extension Account {
    var profileFile: URL {
        isDefault ? Account.home.appendingPathComponent(".claude.json") : dir.appendingPathComponent(".claude.json")
    }

    func loadProfile() -> AccountProfile {
        guard let data = try? Data(contentsOf: profileFile),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = obj["oauthAccount"] as? [String: Any] else { return AccountProfile() }
        return AccountProfile(email: oauth["emailAddress"] as? String, plan: planName(oauth))
    }

    /// "claude_max" + "default_claude_max_20x" -> "Max 20×"; "claude_team" + "team_standard" -> "Team Standard"
    private func planName(_ oauth: [String: Any]) -> String? {
        guard let type = oauth["organizationType"] as? String, type.hasPrefix("claude_") else { return nil }
        var name = type.dropFirst("claude_".count).capitalized
        let tier = [oauth["userRateLimitTier"], oauth["organizationRateLimitTier"]].compactMap { $0 as? String }.joined()
        if tier.contains("20x") { name += " 20×" } else if tier.contains("5x") { name += " 5×" }
        if let seat = oauth["seatTier"] as? String, let level = seat.split(separator: "_").last, seat.contains("_") {
            name += " \(level.capitalized)"
        }
        return name
    }
}

// MARK: - Active account (which one plain `claude` starts)

extension Accounts {
    /// Read by the `claude` shell function: the selected account's folder, empty for the default.
    static let activeFile = Account.main.dir.appendingPathComponent("claudemeter/active-account")

    static var activeID: String {
        UserDefaults.standard.string(forKey: "activeAccount") ?? Account.main.id
    }

    static func setActive(_ account: Account) {
        UserDefaults.standard.set(account.id, forKey: "activeAccount")
        try? (account.isDefault ? "" : account.path).write(to: activeFile, atomically: true, encoding: .utf8)
    }
}
