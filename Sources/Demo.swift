import Foundation

/// Made-up but realistic data for screenshots (`--snapshot <dir> --demo`),
/// so no real email, project or usage ever appears in docs.
enum Demo {
    static func store(now: Date = Date()) -> UsageStore {
        let personal = Account(id: "default", name: "Personal", path: "/demo/.claude")
        let work = Account(id: "work", name: "Work", path: "/demo/.claude-work")
        var rng = SeededGenerator(seed: 42)

        let personalEntries = entries(account: personal.id, projects: ["api-server", "web-app", "dotfiles"],
                                      model: "claude-opus-5-5", scale: 1, now: now, rng: &rng)
        let workEntries = entries(account: work.id, projects: ["billing-service", "docs-site"],
                                  model: "claude-sonnet-5-5", scale: 0.6, now: now, rng: &rng)

        var personalLive = LiveData()
        personalLive.fiveHour = Limit(usedPercent: 48, resetsAt: now.addingTimeInterval(3 * 3600 + 12 * 60))
        personalLive.sevenDay = Limit(usedPercent: 31, resetsAt: now.addingTimeInterval(3 * 86400))
        personalLive.modelWeeks = [ModelLimit(name: "Sonnet only", limit: Limit(usedPercent: 18, resetsAt: now.addingTimeInterval(3 * 86400)))]
        personalLive.limitsUpdated = now
        personalLive.lastReport = now
        personalLive.sessions = [
            session("api-server", account: personal.id, model: "Opus 5.5", context: 42, quiet: 8, now: now),
            session("web-app", account: personal.id, model: "Opus 5.5", context: 67, quiet: 4 * 60, now: now),
        ]

        var workLive = LiveData()
        workLive.fiveHour = Limit(usedPercent: 12, resetsAt: now.addingTimeInterval(100 * 60))
        workLive.limitsUpdated = now.addingTimeInterval(-3 * 60)
        workLive.lastReport = workLive.limitsUpdated

        let personalSnap = summarize(personalEntries, hasLogs: true, live: personalLive,
                                     history: limitHistory(current: personalLive.fiveHour!, now: now, rng: &rng), now: now)
        let workSnap = summarize(workEntries, hasLogs: true, live: workLive, now: now)
        let allSnap = summarize((personalEntries + workEntries).sorted { $0.date < $1.date }, hasLogs: true,
                                live: .merged([personalLive, workLive]), now: now)

        return UsageStore(demoAccounts: [personal, work],
                          snaps: [personal.id: personalSnap, work.id: workSnap, UsageStore.all: allSnap],
                          profiles: [personal.id: AccountProfile(email: "you@example.com", plan: "Max 20×"),
                                     work.id: AccountProfile(email: "you@company.com", plan: "Team Standard")],
                          active: personal.id)
    }

    /// A month of 5-hour windows: a few per weekday, ramping to a peak, a couple at the limit.
    private static func limitHistory(current: Limit, now: Date, rng: inout SeededGenerator) -> [LimitSample] {
        let cal = Calendar.current
        var out: [LimitSample] = []
        for day in (1..<30).reversed() {
            let start = cal.startOfDay(for: now).addingTimeInterval(-Double(day) * 86400)
            if cal.isDateInWeekend(start) && Bool.random(using: &rng) { continue }
            for hour in [9.0, 14.0, 19.0] where Double.random(in: 0...1, using: &rng) < 0.8 {
                let open = start.addingTimeInterval(hour * 3600)
                let reset = open.addingTimeInterval(WindowStats.length)
                let peak = Double.random(in: 0...1, using: &rng) < 0.08 ? 100 : Double.random(in: 15...92, using: &rng)
                for step in 0...12 {
                    let t = open.addingTimeInterval(Double(step) * 20 * 60)
                    let f = (peak * Double(step) / 12).rounded()
                    out.append(LimitSample(t: t.timeIntervalSince1970, f: f, fr: reset.timeIntervalSince1970, w: nil))
                }
            }
        }
        // The current window, climbing to its present value over the last hour
        for step in 0...6 {
            let t = now.addingTimeInterval(-Double(6 - step) * 10 * 60)
            out.append(LimitSample(t: t.timeIntervalSince1970, f: (current.usedPercent - 18 + 3 * Double(step)).rounded(),
                                   fr: current.resetsAt.timeIntervalSince1970, w: 31))
        }
        return out
    }

    private static func session(_ project: String, account: String, model: String, context: Double,
                                quiet: TimeInterval, now: Date) -> LiveSession {
        LiveSession(id: "\(account)-\(project)", account: account, model: model, project: project,
                    contextPercent: context, contextTokens: Int(context * 10_000), contextSize: 1_000_000,
                    updated: now.addingTimeInterval(-quiet), lastActivity: now.addingTimeInterval(-quiet))
    }

    /// Three weeks of weekday-heavy usage, plus a busy last few hours.
    private static func entries(account: String, projects: [String], model: String, scale: Double,
                                now: Date, rng: inout SeededGenerator) -> [Entry] {
        let cal = Calendar.current
        var out: [Entry] = []
        func add(_ date: Date, session: String) {
            out.append(Entry(date: date, model: model, project: projects.randomElement(using: &rng)!,
                             session: session, account: account,
                             input: Int.random(in: 2...40, using: &rng),
                             output: Int.random(in: 400...4_000, using: &rng),
                             cacheRead: Int.random(in: 40_000...200_000, using: &rng),
                             cacheWrite5m: 0, cacheWrite1h: Int.random(in: 500...12_000, using: &rng)))
        }
        for day in 1..<21 {
            let start = cal.startOfDay(for: now).addingTimeInterval(-Double(day) * 86400)
            let weekend = cal.isDateInWeekend(start)
            let count = Int(Double.random(in: 10...34, using: &rng) * scale * (weekend ? 0.2 : 1))
            for _ in 0..<count {
                let hour = Double.random(in: 9...22, using: &rng)
                add(start.addingTimeInterval(hour * 3600), session: "\(account)-\(day)-\(Int(hour / 3))")
            }
        }
        // Today: steady through the day, busiest in the last two hours
        let today = cal.startOfDay(for: now)
        let hoursSoFar = now.timeIntervalSince(today) / 3600
        for _ in 0..<Int(30 * scale) {
            let hour = Double.random(in: max(0, hoursSoFar - 9)...hoursSoFar, using: &rng)
            add(today.addingTimeInterval(hour * 3600), session: "\(account)-today-\(Int(hour / 3))")
        }
        for _ in 0..<Int(24 * scale) {
            let ago = Double.random(in: 60...(2 * 3600), using: &rng)
            add(now.addingTimeInterval(-ago), session: "\(account)-\(projects[0])")
        }
        return out.filter { $0.date <= now }.sorted { $0.date < $1.date }
    }
}

/// Deterministic randomness, so demo screenshots are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
