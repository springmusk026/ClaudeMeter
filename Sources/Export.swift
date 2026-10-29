import AppKit

/// `ClaudeMeter --json` prints current usage for scripts, Raycast, SketchyBar and
/// similar. Asks Claude Code for fresh limits first unless `--no-probe` is given.
enum UsageExport {
    static func json(_ store: UsageStore, now: Date = Date()) -> Data {
        let iso = ISO8601DateFormatter()
        func limit(_ l: Limit?) -> Any {
            guard let l else { return NSNull() }
            return ["used_percent": l.usedPercent, "resets_at": iso.string(from: l.resetsAt)]
        }
        func money(_ v: Double) -> NSDecimalNumber { NSDecimalNumber(string: String(format: "%.2f", v)) }

        let accounts: [[String: Any]] = store.accounts.map { a in
            let s = store.snap(a.id)
            let profile = store.profile(a.id)
            var obj: [String: Any] = [
                "id": a.id,
                "name": a.name,
                "active": store.activeID == a.id,
                "signed_in": profile.signedIn,
                "plan": profile.plan ?? NSNull(),
                "limits": [
                    "five_hour": limit(s.live.fiveHour),
                    "weekly": limit(s.live.sevenDay),
                    "weekly_by_model": s.live.modelWeeks.map { ["model": $0.name, "limit": limit($0.limit)] },
                    "updated_at": s.live.limitsUpdated.map(iso.string) ?? NSNull(),
                ],
                "today": ["cost_usd": money(s.today.cost), "tokens": s.today.tokens,
                          "messages": s.today.messages, "sessions": s.todaySessions],
                "last_7_days": ["cost_usd": money(s[.week].total.cost), "tokens": s[.week].total.tokens],
                "open_sessions": s.live.sessions.map {
                    ["project": $0.project, "model": $0.model,
                     "working": Activity(last: $0.lastActivity, now: now) == .working,
                     "context_percent": $0.contextPercent ?? NSNull()] as [String: Any]
                },
            ]
            if let f = s.window?.limitForecast(now: now) {
                obj["forecast"] = ["projected_percent": f.projected.rounded(),
                                   "limit_reached_at": f.hitAt.map { iso.string(from: $0) as Any } ?? NSNull()] as [String: Any]
            }
            return obj
        }
        let all = store.snap(UsageStore.all)
        let root: [String: Any] = [
            "generated_at": iso.string(from: now),
            "accounts": accounts,
            "total": ["today_cost_usd": money(all.today.cost), "today_tokens": all.today.tokens,
                      "last_7_days_cost_usd": money(all[.week].total.cost)],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

extension UsageStore {
    /// A report for bug reports: versions, setup and data health. No emails,
    /// account names or project names.
    func diagnostics(now: Date = Date()) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let settings = (try? String(contentsOf: Account.main.dir.appendingPathComponent("settings.json"), encoding: .utf8)) ?? ""
        var lines = [
            "ClaudeMeter \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Claude Code: \(Accounts.claudePath.hasPrefix("/") ? "found" : "not found in usual places")",
            "Status line installed: \(settings.contains("statusline.sh") ? "yes" : "no")",
            "Terminal commands installed: \(Accounts.shellCommandsInstalled ? "yes" : "no")",
            "Limit checks: \(UserDefaults.standard.bool(forKey: "probeLimits") ? "on" : "off"), last \(lastProbe.map { "\(Int(now.timeIntervalSince($0)))s ago" } ?? "never"), failures \(probeFailures)",
            "Thresholds: warn \(Int(Thresholds.warn))%, critical \(Int(Thresholds.critical))%",
            "Accounts: \(accounts.count)",
        ]
        for (i, a) in accounts.enumerated() {
            let s = snap(a.id)
            let age = { (d: Date?) in d.map { "\(Int(now.timeIntervalSince($0)))s ago" } ?? "never" }
            lines.append("""
            Account \(i + 1)\(a.isDefault ? " (default)" : ""): signed in \(profile(a.id).signedIn ? "yes" : "no"), \
            plan \(profile(a.id).plan ?? "unknown"), logs \(s.hasLogs ? "yes" : "no"), \
            7d messages \(s[.week].total.messages), 5h \(s.live.fiveHour.map { "\(Int($0.usedPercent))%" } ?? "none"), \
            weekly \(s.live.sevenDay.map { "\(Int($0.usedPercent))%" } ?? "none"), model weeks \(s.live.modelWeeks.count), \
            limits updated \(age(s.live.limitsUpdated)), last report \(age(s.live.lastReport)), \
            open sessions \(s.live.sessions.count), history samples \(s.limitSamples.count)
            """)
        }
        let unpriced = snap(Self.all).unpriced
        if !unpriced.isEmpty { lines.append("Unpriced models: \(unpriced.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics(), forType: .string)
    }
}
