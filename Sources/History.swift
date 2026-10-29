import Foundation

/// One reading of an account's plan limits.
struct LimitSample: Codable {
    let t: TimeInterval          // when
    let f: Double?               // 5-hour % used
    let fr: TimeInterval?        // 5-hour window reset
    let w: Double?               // weekly % used (all models)

    var date: Date { Date(timeIntervalSince1970: t) }
}

/// Plan limit readings per account for the last 30 days, kept in
/// ~/Library/Application Support/ClaudeMeter/history/<account>.json.
/// Recorded whenever a value changes, and at least every few minutes while in use.
final class LimitHistory {
    static let dir = Account.home.appendingPathComponent("Library/Application Support/ClaudeMeter/history")
    static let keep: TimeInterval = 31 * 86400

    private var samples: [String: [LimitSample]] = [:]
    private let lock = NSLock()

    func samples(for account: String) -> [LimitSample] {
        lock.lock(); defer { lock.unlock() }
        if samples[account] == nil { samples[account] = Self.read(account) }
        return samples[account] ?? []
    }

    /// Adds a reading if it differs from the last one or the last is a few minutes old.
    func record(_ live: LiveData, account: String, now: Date = Date()) {
        guard live.hasLimits else { return }
        let sample = LimitSample(t: now.timeIntervalSince1970,
                                 f: live.fiveHour?.usedPercent,
                                 fr: live.fiveHour?.resetsAt.timeIntervalSince1970,
                                 w: live.sevenDay?.usedPercent)
        var list = samples(for: account)
        if let last = list.last, sample.t - last.t < 4.5 * 60,
           last.f == sample.f, last.w == sample.w, last.fr.map({ abs($0 - (sample.fr ?? 0)) < 120 }) ?? true {
            return
        }
        list.append(sample)
        list.removeAll { sample.t - $0.t > Self.keep }
        lock.lock(); samples[account] = list; lock.unlock()
        Self.write(list, account: account)
    }

    private static func file(_ account: String) -> URL { dir.appendingPathComponent("\(account).json") }

    private static func read(_ account: String) -> [LimitSample] {
        guard let data = try? Data(contentsOf: file(account)) else { return [] }
        return (try? JSONDecoder().decode([LimitSample].self, from: data)) ?? []
    }

    private static func write(_ list: [LimitSample], account: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: file(account), options: .atomic) }
    }
}

extension Array where Element == LimitSample {
    /// 5-hour usage per hour of the last day, from readings in the current window,
    /// so a fresh window doesn't look like a sudden drop.
    func recentRate(window: Limit, now: Date) -> Double? {
        let reset = window.resetsAt.timeIntervalSince1970
        let recent = filter { s in
            s.f != nil && abs((s.fr ?? 0) - reset) < 120 && now.timeIntervalSince(s.date) <= 3600
        }
        guard let first = recent.first, let last = recent.last, let a = first.f, let b = last.f else { return nil }
        let hours = (last.t - first.t) / 3600
        guard hours >= 0.25 else { return nil }
        return Swift.max(0, b - a) / hours
    }
}
