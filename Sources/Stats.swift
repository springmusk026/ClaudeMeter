import Foundation

enum Period: String, CaseIterable, Identifiable {
    case today, week, month
    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week:  return "7 Days"
        case .month: return "30 Days"
        }
    }

    /// Chart bar size
    var unit: Calendar.Component { self == .today ? .hour : .day }

    var axisStride: Int {
        switch self {
        case .today: return 6
        case .week:  return 1
        case .month: return 7
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .today: return .dateTime.hour()
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).day()
        }
    }

    func start(now: Date, cal: Calendar) -> Date {
        let today = cal.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week:  return cal.date(byAdding: .day, value: -6, to: today)!
        case .month: return cal.date(byAdding: .day, value: -29, to: today)!
        }
    }
}

struct Share: Identifiable {
    let name: String
    let bucket: Bucket
    var id: String { name }
}

struct Point: Identifiable {
    let date: Date
    let bucket: Bucket
    var id: Date { date }
}

struct PeriodStats {
    var start = Date(), end = Date()
    var chartStart = Date()   // later than `start` while there's less history than the period
    var total = Bucket()
    var models: [Share] = []
    var projects: [Share] = []
    var series: [Point] = []
}

/// The current 5-hour usage window. When Claude Code reports the plan limit, its
/// reset time is exact. Otherwise we approximate: a window opens on the hour of the
/// first message after the previous one ended.
struct WindowStats {
    static let length: TimeInterval = 5 * 3600

    let start: Date
    let firstActivity: Date
    let bucket: Bucket
    var limit: Limit?
    var recentRate: Double?        // limit % per hour over the last hour, from saved readings
    var end: Date { start.addingTimeInterval(Self.length) }

    private func activeHours(now: Date, atLeast minutes: Double) -> Double? {
        let hours = now.timeIntervalSince(firstActivity) / 3600
        return hours < minutes / 60 ? nil : hours
    }

    /// Spend per hour, once there's enough history for the figure to mean something.
    func costPerHour(now: Date) -> Double? {
        activeHours(now: now, atLeast: 45).map { bucket.cost / $0 }
    }

    /// Where the plan limit is heading at the current pace: the time it would be
    /// hit, or the share expected to be used by the reset. The pace comes from
    /// the last hour of saved readings when there are enough; otherwise from the
    /// average since the window's first message, which early on is mostly noise,
    /// so that waits for 30 minutes of activity and 25% used.
    func limitForecast(now: Date) -> (hitAt: Date?, projected: Double)? {
        guard let limit else { return nil }
        let perHour: Double
        if let recentRate {
            perHour = recentRate
        } else {
            guard limit.usedPercent >= 25, let hours = activeHours(now: now, atLeast: 30) else { return nil }
            perHour = limit.usedPercent / hours
        }
        guard perHour > 0 else { return nil }
        let projected = limit.usedPercent + perHour * max(0, end.timeIntervalSince(now)) / 3600
        guard projected >= 100 else { return (nil, projected) }
        return (now.addingTimeInterval((100 - limit.usedPercent) / perHour * 3600), projected)
    }
}

struct SessionStats: Identifiable {
    let id: String
    var project: String
    var model: String
    var start: Date
    var end: Date
    var bucket = Bucket()

    func isActive(now: Date) -> Bool { now.timeIntervalSince(end) < 5 * 60 }
}

struct Snapshot {
    var periods: [Period: PeriodStats] = [:]
    var window: WindowStats?
    var sessions: [SessionStats] = []
    var live = LiveData()
    var limitSamples: [LimitSample] = []   // saved plan limit readings, oldest first
    var previousWeek = Bucket()   // the 7 days before the last 7
    var todaySessions = 0
    var unpriced: [String] = []   // models we have no price for
    var hasLogs = false
    var updated: Date?

    subscript(p: Period) -> PeriodStats { periods[p] ?? PeriodStats() }
    var today: Bucket { self[.today].total }
}

func summarize(_ entries: [Entry], hasLogs: Bool, live: LiveData, history: [LimitSample] = [],
               now: Date = Date()) -> Snapshot {
    let cal = Calendar.current
    var s = Snapshot()
    s.hasLogs = hasLogs
    s.live = live
    s.updated = now
    let firstDay = entries.first.map { cal.startOfDay(for: $0.date) } ?? cal.startOfDay(for: now)
    for p in Period.allCases { s.periods[p] = periodStats(entries, p, firstDay: firstDay, now: now, cal: cal) }
    s.window = currentWindow(entries, limit: live.fiveHour, now: now, cal: cal)
    if let limit = live.fiveHour { s.window?.recentRate = history.recentRate(window: limit, now: now) }
    s.limitSamples = history
    s.live = withLogActivity(live, entries, now: now)
    s.sessions = recentSessions(entries)

    let today = cal.startOfDay(for: now)
    s.todaySessions = Set(entries.reversed().prefix { $0.date >= today }.map(\.session)).count
    let weekStart = s[.week].start
    let previousStart = cal.date(byAdding: .day, value: -7, to: weekStart)!
    for e in entries where e.date >= previousStart && e.date < weekStart { s.previousWeek.add(e) }
    s.unpriced = Set(entries.lazy.filter { rate(for: $0.model) == nil }.map(\.model)).sorted()
    return s
}

private func periodStats(_ entries: [Entry], _ p: Period, firstDay: Date, now: Date, cal: Calendar) -> PeriodStats {
    var st = PeriodStats()
    st.start = p.start(now: now, cal: cal)
    st.end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
    // Don't draw a month of empty days before the first activity, but always show a week
    let weekStart = Period.week.start(now: now, cal: cal)
    st.chartStart = p == .month ? max(st.start, min(firstDay, weekStart)) : st.start

    var models: [String: Bucket] = [:], projects: [String: Bucket] = [:], slots: [Date: Bucket] = [:]
    // Entries are oldest first, so walk back from the newest and stop at the period start
    for e in entries.reversed() {
        if e.date < st.start { break }
        st.total.add(e)
        models[modelName(e.model), default: Bucket()].add(e)
        projects[e.project, default: Bucket()].add(e)
        slots[cal.dateInterval(of: p.unit, for: e.date)!.start, default: Bucket()].add(e)
    }
    st.models = ranked(models)
    st.projects = ranked(projects)
    st.series = slots.map { Point(date: $0.key, bucket: $0.value) }
        .sorted { $0.date < $1.date }
    return st
}

private func ranked(_ d: [String: Bucket]) -> [Share] {
    d.map { Share(name: $0.key, bucket: $0.value) }
        .sorted { ($0.bucket.cost, $0.bucket.tokens) > ($1.bucket.cost, $1.bucket.tokens) }
}

private func currentWindow(_ entries: [Entry], limit: Limit?, now: Date, cal: Calendar) -> WindowStats? {
    // Exact window from the reported limit; usage on claude.ai can open it without any local log
    if let limit {
        let start = limit.resetsAt.addingTimeInterval(-WindowStats.length)
        var bucket = Bucket()
        var first: Date?
        for e in entries.reversed() {
            if e.date < start { break }
            bucket.add(e)
            first = e.date
        }
        return WindowStats(start: start, firstActivity: first ?? start, bucket: bucket, limit: limit)
    }

    var start: Date?
    var first = now
    var bucket = Bucket()
    for e in entries {
        if start == nil || e.date >= start!.addingTimeInterval(WindowStats.length) {
            start = cal.dateInterval(of: .hour, for: e.date)!.start
            first = e.date
            bucket = Bucket()
        }
        bucket.add(e)
    }
    guard let start, now < start.addingTimeInterval(WindowStats.length) else { return nil }
    return WindowStats(start: start, firstActivity: first, bucket: bucket)
}

private func recentSessions(_ entries: [Entry], limit: Int = 6) -> [SessionStats] {
    var sessions: [String: SessionStats] = [:]
    for e in entries {
        var s = sessions[e.session]
            ?? SessionStats(id: e.session, project: e.project, model: "", start: e.date, end: e.date)
        s.end = e.date
        s.model = modelName(e.model)
        s.bucket.add(e)
        sessions[e.session] = s
    }
    return Array(sessions.values.sorted { $0.end > $1.end }.prefix(limit))
}

/// Status lines only refresh while Claude Code redraws, so a session's latest
/// logged response also counts as activity.
private func withLogActivity(_ live: LiveData, _ entries: [Entry], now: Date) -> LiveData {
    var lastLogged: [String: Date] = [:]
    for e in entries.reversed() {
        if now.timeIntervalSince(e.date) > LiveReader.openFor { break }
        if lastLogged[e.session] == nil { lastLogged[e.session] = e.date }
    }
    var live = live
    for i in live.sessions.indices {
        if let logged = lastLogged[live.sessions[i].id] {
            live.sessions[i].lastActivity = max(live.sessions[i].lastActivity, logged)
        }
    }
    live.sessions.sort { $0.lastActivity > $1.lastActivity }
    return live
}
