import SwiftUI
import UserNotifications

/// What the user most needs to know right now, most urgent first.
enum PanelState {
    case loading
    case limitReached(account: String?, kind: String, resetsAt: Date, alternative: String?)
    case working(project: String, model: String, others: Int)
    case idle(since: Date)
    case noSession
}

final class UsageStore: ObservableObject {
    /// Scope id for all accounts combined
    static let all = "all"

    @Published private(set) var accounts = Accounts.load()
    @Published private(set) var snaps: [String: Snapshot] = [:]
    @Published private(set) var profiles: [String: AccountProfile] = [:]
    @Published private(set) var activeID = Accounts.activeID
    @Published private(set) var loading = true
    @Published private(set) var lastProbe: Date?
    @Published private(set) var probeFailures = 0

    private let reader = LogReader()
    let history = LimitHistory()
    private var probes: [String: UsageReport] = [:]
    private let probeQueue = DispatchQueue(label: "ClaudeMeter.probe", qos: .utility)
    private var probing = false
    private var probeTimer: Timer?
    private let queue = DispatchQueue(label: "ClaudeMeter.logs", qos: .utility)
    private var watcher: FolderWatcher?
    private var timer: Timer?
    private var busy = false
    private var pending = false

    init() {
        UserDefaults.standard.register(defaults: ["limitAlerts": true, "probeLimits": true, "weeklyInIcon": true])
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        if UserDefaults.standard.bool(forKey: "limitAlerts") { Alerts.requestPermission() }
        accounts.forEach(Accounts.prepare)
        Accounts.writeShellCommands(accounts)

        refresh()
        watch()
        // Time moves on even when nothing is logged: the day rolls over, windows expire
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        probeLimits(force: true)
        probeTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.probeLimits(force: true)
        }
    }

    /// For snapshots and `--json`: loads once, synchronously, with no watchers or notifications.
    /// With `probe`, also asks Claude Code for each account's limits first.
    init(preview: Bool, probe: Bool = false) {
        if probe {
            for a in accounts where a.loadProfile().signedIn {
                if let r = UsageProbe.run(a) { probes[a.id] = r }
            }
        }
        (snaps, profiles) = Self.compute(accounts, reader, probes: probes, history: history)
        loading = false
    }

    /// For demo screenshots: fixed data, nothing read from disk.
    init(demoAccounts: [Account], snaps: [String: Snapshot], profiles: [String: AccountProfile], active: String) {
        accounts = demoAccounts
        self.snaps = snaps
        self.profiles = profiles
        activeID = active
        loading = false
    }

    var multiAccount: Bool { accounts.count > 1 }

    func snap(_ scope: String) -> Snapshot { snaps[scope] ?? snaps[Self.all] ?? Snapshot() }

    func account(_ id: String) -> Account? { accounts.first { $0.id == id } }

    func profile(_ id: String) -> AccountProfile { profiles[id] ?? AccountProfile() }

    var activeAccount: Account { account(activeID) ?? .main }

    /// The account being worked in: the one with the latest activity in the last
    /// few minutes, otherwise the one selected for new sessions.
    var currentAccount: Account {
        let recent = accounts.compactMap { a -> (Account, Date)? in
            guard let last = snap(a.id).live.sessions.first?.lastActivity,
                  Date().timeIntervalSince(last) < LiveReader.openFor else { return nil }
            return (a, last)
        }
        return recent.max { $0.1 < $1.1 }?.0 ?? activeAccount
    }

    func state(now: Date = Date()) -> PanelState {
        if loading && snaps.isEmpty { return .loading }

        for a in accounts {
            let live = snap(a.id).live
            for (kind, limit) in [("5-hour", live.fiveHour), ("weekly", live.sevenDay)] {
                guard let limit, limit.usedPercent >= 100 else { continue }
                let other = accounts.first { $0.id != a.id && (snap($0.id).live.fiveHour?.usedPercent ?? 101) < Thresholds.warn }
                let alternative = other.map {
                    "\($0.name) has \(Int(100 - (snap($0.id).live.fiveHour?.usedPercent ?? 0)))% left"
                }
                return .limitReached(account: multiAccount ? a.name : nil, kind: kind,
                                     resetsAt: limit.resetsAt, alternative: alternative)
            }
        }

        let all = snap(Self.all)
        let working = all.live.sessions.filter { Activity(last: $0.lastActivity, now: now) == .working }
        if let first = working.first {
            return .working(project: first.project, model: first.model, others: working.count - 1)
        }
        if let last = [all.live.sessions.first?.lastActivity, all.sessions.first?.end].compactMap({ $0 }).max() {
            return .idle(since: last)
        }
        return .noSession
    }

    /// Selects the account that new `claude` sessions (and ClaudeMeter's launcher) use.
    func setActive(_ id: String) {
        guard let account = account(id) else { return }
        Accounts.setActive(account)
        activeID = id
    }

    // MARK: Accounts

    func addAccount(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = Accounts.makeID(trimmed, taken: Set(accounts.map(\.id)))
        let account = Account(id: id, name: trimmed, path: Account.home.appendingPathComponent(".claude-\(id)").path)
        Accounts.prepare(account)
        accounts.append(account)
        accountsChanged()
    }

    func rename(_ id: String, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name
        Accounts.save(accounts)
    }

    /// Stops tracking an account. Its folder and login are left in place.
    func remove(_ id: String) {
        guard id != Account.main.id else { return }
        if activeID == id { setActive(Account.main.id) }
        accounts.removeAll { $0.id == id }
        accountsChanged()
    }

    // MARK: Limits from Claude Code

    /// Asks Claude Code (`claude -p /usage`, local and free) for each signed-in
    /// account's limits. Runs every 5 minutes and when the panel opens.
    func probeLimits(force: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "probeLimits"), !probing else { return }
        if !force, let last = lastProbe, Date().timeIntervalSince(last) < 60 { return }
        probing = true
        let targets = accounts
        probeQueue.async { [weak self] in
            var results: [String: UsageReport] = [:]
            var tried = 0
            for a in targets where a.loadProfile().signedIn {
                tried += 1
                if let report = UsageProbe.run(a) { results[a.id] = report }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.probes.merge(results) { $1 }
                self.lastProbe = Date()
                self.probeFailures = tried - results.count
                self.probing = false
                self.refresh()
            }
        }
    }

    private func accountsChanged() {
        Accounts.save(accounts)
        watch()
        refresh()
    }

    // MARK: Refreshing

    /// Logs change as Claude works; live files change whenever a status line refreshes.
    private func watch() {
        let paths = accounts.flatMap { [$0.projects.path, $0.liveDir.path] }
        watcher = FolderWatcher(paths: paths) { [weak self] in self?.refresh() }
    }

    func refresh() {
        if busy { pending = true; return }
        busy = true
        let accounts = self.accounts
        let probes = self.probes
        queue.async { [weak self] in
            guard let self else { return }
            let (snaps, profiles) = Self.compute(accounts, self.reader, probes: probes, history: self.history)
            for a in accounts { self.history.record(snaps[a.id]?.live ?? LiveData(), account: a.id) }
            DispatchQueue.main.async {
                self.snaps = snaps
                self.profiles = profiles
                self.loading = false
                self.busy = false
                Alerts.update(accounts: accounts, snaps: snaps)
                StatusFile.write(accounts: accounts, snaps: snaps)
                WidgetFeed.update(self)
                if self.pending {
                    self.pending = false
                    self.refresh()
                }
            }
        }
    }
}

extension UsageStore {
    /// Stats per account, plus all accounts combined under `all`.
    fileprivate static func compute(_ accounts: [Account], _ reader: LogReader,
                                    probes: [String: UsageReport], history: LimitHistory)
        -> ([String: Snapshot], [String: AccountProfile]) {
        let entries = reader.load(accounts)
        var snaps: [String: Snapshot] = [:]
        var profiles: [String: AccountProfile] = [:]
        var lives: [LiveData] = []
        for a in accounts {
            profiles[a.id] = a.loadProfile()
            var live = LiveReader.load(dir: a.liveDir, account: a.id)
            if let report = probes[a.id] { live.apply(report) }
            lives.append(live)
            let own = entries.filter { $0.account == a.id }
            snaps[a.id] = summarize(own, hasLogs: !own.isEmpty, live: live, history: history.samples(for: a.id))
        }
        snaps[all] = accounts.count == 1
            ? snaps[accounts[0].id]
            : summarize(entries, hasLogs: !entries.isEmpty, live: .merged(lives))
        return (snaps, profiles)
    }
}

// MARK: - Notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // Show banners even while the panel is open
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum Alerts {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func update(accounts: [Account], snaps: [String: Snapshot]) {
        let defaults = UserDefaults.standard

        // Budget covers all accounts: alert once per day per level (1 = 80%, 2 = 100%)
        let budget = defaults.double(forKey: "dailyBudget")
        if defaults.bool(forKey: "budgetAlerts"), budget > 0 {
            let spent = snaps[UsageStore.all]?.today.cost ?? 0
            let level = spent >= budget ? 2 : spent >= budget * 0.8 ? 1 : 0
            let day = dayStamp()
            let last = defaults.string(forKey: "lastBudgetAlert") ?? ""
            let lastLevel = last.hasPrefix(day) ? Int(last.split(separator: ":").last ?? "") ?? 0 : 0
            if level > lastLevel {
                defaults.set("\(day):\(level)", forKey: "lastBudgetAlert")
                post(id: "budget",
                     title: level == 2 ? "Daily budget reached" : "80% of daily budget used",
                     body: "\(fmtCost(spent)) of \(fmtCost(budget)) spent today.")
            }
        }

        for account in accounts {
            let s = snaps[account.id] ?? Snapshot()
            let prefix = accounts.count > 1 ? "\(account.name): " : ""

            // Plan limits: alert once per limit period per level (1 = 80%, 2 = 95%)
            if defaults.bool(forKey: "limitAlerts") {
                let limits = [("5-hour", s.live.fiveHour), ("Weekly", s.live.sevenDay)]
                    + s.live.modelWeeks.map { ("Weekly \($0.name)", Optional($0.limit)) }
                for (name, limit) in limits {
                    guard let limit else { continue }
                    let level = limit.usedPercent >= Thresholds.critical ? 2 : limit.usedPercent >= Thresholds.warn ? 1 : 0
                    let key = "lastLimitAlert-\(account.id)-\(name)"
                    let period = "\(Int(limit.resetsAt.timeIntervalSince1970))"
                    let last = defaults.string(forKey: key) ?? ""
                    let lastLevel = last.hasPrefix(period + ":") ? Int(last.split(separator: ":").last ?? "") ?? 0 : 0
                    if level > lastLevel {
                        defaults.set("\(period):\(level)", forKey: key)
                        let resets = name.hasPrefix("Weekly")
                            ? limit.resetsAt.formatted(.dateTime.weekday(.wide).hour().minute())
                            : limit.resetsAt.formatted(date: .omitted, time: .shortened)
                        post(id: "limit-\(account.id)-\(name)",
                             title: "\(prefix)\(name) limit \(Int(limit.usedPercent))% used",
                             body: "Resets \(resets).")
                    }
                }
            }

            // Window reset: keep one notification scheduled for each window's end
            let resetID = "window-reset-\(account.id)"
            if defaults.bool(forKey: "resetAlerts"), let w = s.window {
                post(id: resetID, title: "\(prefix)5-hour window reset",
                     body: "The last window used \(fmtCost(w.bucket.cost)) · \(fmtTokens(w.bucket.tokens)) tokens.",
                     at: w.end)
            } else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [resetID])
            }
        }
    }

    private static func post(id: String, title: String, body: String, at date: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = date.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }
}

// MARK: - Shared summary for the Claude Code status line

/// Writes <account folder>/claudemeter.json so ~/.claude/statusline.sh can show
/// the account's name, window and daily totals.
enum StatusFile {
    private static var last: [String: Data] = [:]

    static func write(accounts: [Account], snaps: [String: Snapshot]) {
        for account in accounts {
            let s = snaps[account.id] ?? Snapshot()
            var obj: [String: Any] = [
                "account": account.name,
                "accounts": accounts.count,
                "day": dayStamp(),
                "today_cost": (s.today.cost * 100).rounded() / 100,
                "today_tokens": s.today.tokens,
                "daily_budget": UserDefaults.standard.double(forKey: "dailyBudget"),
                "warn_at": Thresholds.warn,
                "critical_at": Thresholds.critical,
            ]
            if let w = s.window {
                obj["window_cost"] = (w.bucket.cost * 100).rounded() / 100
                obj["window_tokens"] = w.bucket.tokens
                obj["window_end"] = Int(w.end.timeIntervalSince1970)
            }
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                  data != last[account.id] else { continue }
            last[account.id] = data
            try? data.write(to: account.summaryFile, options: .atomic)
        }
    }
}
