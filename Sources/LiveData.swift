import Foundation

/// A plan limit as reported by Claude Code (subscription accounts only).
struct Limit {
    let usedPercent: Double
    let resetsAt: Date
}

/// An open Claude Code session's latest state.
struct LiveSession: Identifiable {
    let id: String
    let account: String
    let model: String
    let project: String
    let contextPercent: Double?
    let contextTokens: Int?
    let contextSize: Int?
    let updated: Date
    /// Latest sign of life: a status line report or a logged response
    var lastActivity: Date
}

enum Activity {
    case working, idle, closed

    init(last: Date, now: Date) {
        let quiet = now.timeIntervalSince(last)
        self = quiet < 60 ? .working : quiet < LiveReader.openFor ? .idle : .closed
    }
}

struct LiveData {
    var fiveHour: Limit?
    var sevenDay: Limit?
    var limitsUpdated: Date?
    var lastReport: Date?          // newest status line report of any kind
    var sessions: [LiveSession] = []

    var hasLimits: Bool { fiveHour != nil || sevenDay != nil }

    /// Open sessions across accounts. Limits belong to one account, so none carry over.
    static func merged(_ all: [LiveData]) -> LiveData {
        var live = LiveData()
        live.sessions = all.flatMap(\.sessions).sorted { $0.updated > $1.updated }
        live.lastReport = all.compactMap(\.lastReport).max()
        return live
    }
}

/// Reads what ~/.claude/statusline.sh saves from Claude Code's status line input:
/// one JSON file per session with its context fill and the account's plan limits.
enum LiveReader {
    /// Sessions not refreshed for this long are no longer shown as open.
    static let openFor: TimeInterval = 15 * 60

    static func load(dir: URL, account: String, now: Date = Date()) -> LiveData {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return LiveData() }

        var live = LiveData()
        var newestLimits: (updated: Date, limits: [String: Any])?
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let stamp = (obj["updated"] as? NSNumber)?.doubleValue else { continue }
            let updated = Date(timeIntervalSince1970: stamp)
            live.lastReport = max(live.lastReport ?? .distantPast, updated)

            // Old sessions are of no further use
            if now.timeIntervalSince(updated) > 2 * 86400 {
                try? fm.removeItem(at: url)
                continue
            }

            // Limits are account-wide, so the most recent report wins
            if let limits = obj["rate_limits"] as? [String: Any], updated > (newestLimits?.updated ?? .distantPast) {
                newestLimits = (updated, limits)
            }

            if now.timeIntervalSince(updated) < openFor {
                let context = obj["context"] as? [String: Any]
                live.sessions.append(LiveSession(
                    id: obj["session_id"] as? String ?? url.deletingPathExtension().lastPathComponent,
                    account: account,
                    model: obj["model"] as? String ?? "Claude",
                    project: obj["project"] as? String ?? "",
                    contextPercent: (context?["used_percentage"] as? NSNumber)?.doubleValue,
                    contextTokens: (context?["total_input_tokens"] as? NSNumber)?.intValue,
                    contextSize: (context?["context_window_size"] as? NSNumber)?.intValue,
                    updated: updated,
                    lastActivity: updated))
            }
        }

        if let (updated, limits) = newestLimits {
            live.fiveHour = limit(limits["five_hour"], now: now)
            live.sevenDay = limit(limits["seven_day"], now: now)
            if live.hasLimits { live.limitsUpdated = updated }
        }
        live.sessions.sort { $0.updated > $1.updated }
        return live
    }

    /// A limit whose reset time has passed no longer applies.
    private static func limit(_ value: Any?, now: Date) -> Limit? {
        guard let dict = value as? [String: Any],
              let used = (dict["used_percentage"] as? NSNumber)?.doubleValue,
              let resets = (dict["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        let resetsAt = Date(timeIntervalSince1970: resets)
        return resetsAt > now ? Limit(usedPercent: used, resetsAt: resetsAt) : nil
    }
}
