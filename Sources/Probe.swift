import Foundation

/// What Claude Code's `/usage` command reports for one account.
struct UsageReport {
    var session: Limit?               // the 5-hour window
    var weekAll: Limit?               // weekly, all models
    var weekModels: [ModelLimit] = [] // weekly limits for one model, e.g. "Sonnet only"
    var fetched: Date
}

/// Asks Claude Code for an account's limits by running `claude -p /usage`.
/// This is a local command: no model request, no cost, and with
/// --no-session-persistence it leaves no session record behind. It lets
/// ClaudeMeter keep limits fresh when no session is open, and adds the
/// per-model weekly limits that status lines don't receive.
enum UsageProbe {
    static func run(_ account: Account, timeout: TimeInterval = 30) -> UsageReport? {
        let process = Process()
        let claude = Accounts.claudePath
        if claude.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: claude)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [claude] + arguments
        }
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = account.isDefault ? nil : account.path
        env["PATH"] = [Account.home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin",
                       env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        process.environment = env
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = obj["result"] as? String else { return nil }
        return parse(text, now: Date())
    }

    private static let arguments = ["-p", "/usage", "--no-session-persistence", "--strict-mcp-config",
                                    "--output-format", "json"]

    // "Current session: 61% used · resets Oct 30 at 1:04am (Asia/Katmandu)"
    // "Current week (all models): 31% used · resets Nov 3 at 9am (Europe/London)"
    // "Current week (Sonnet only): 12% used · resets Nov 3 at 9am (Europe/London)"
    private static let line = try! NSRegularExpression(
        pattern: #"^Current (session|week \((.+)\)):\s*(\d+(?:\.\d+)?)%\s+used(?:\s*·\s*resets\s+(.+))?$"#)

    static func parse(_ text: String, now: Date) -> UsageReport? {
        var report = UsageReport(fetched: now)
        var found = false
        for raw in text.split(separator: "\n") {
            let s = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = line.firstMatch(in: s, range: range) else { continue }
            func group(_ i: Int) -> String? {
                Range(m.range(at: i), in: s).map { String(s[$0]) }
            }
            guard let percent = group(3).flatMap(Double.init) else { continue }
            let resets = group(4).flatMap { resetDate($0, now: now) }
            found = true
            if group(1) == "session" {
                report.session = Limit(usedPercent: percent, resetsAt: resets ?? now.addingTimeInterval(WindowStats.length))
            } else if let scope = group(2), let resets {
                if scope == "all models" {
                    report.weekAll = Limit(usedPercent: percent, resetsAt: resets)
                } else {
                    report.weekModels.append(ModelLimit(name: scope, limit: Limit(usedPercent: percent, resetsAt: resets)))
                }
            }
        }
        return found ? report : nil
    }

    /// "Oct 30 at 1:04am (Asia/Katmandu)", "Nov 3 at 9am", "1:04am" -> the next such moment.
    static func resetDate(_ text: String, now: Date) -> Date? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var zone = TimeZone.current
        if let r = s.range(of: #"\(([^)]+)\)\s*$"#, options: .regularExpression) {
            let name = s[r].trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            zone = TimeZone(identifier: name) ?? zone
            s = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.amSymbol = "am"
        f.pmSymbol = "pm"

        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d, ha", "MMM d"] {
            f.dateFormat = format
            guard let parsed = f.date(from: s) else { continue }
            var parts = cal.dateComponents([.month, .day, .hour, .minute], from: parsed)
            parts.year = cal.component(.year, from: now)
            guard var date = cal.date(from: parts) else { continue }
            if date < now.addingTimeInterval(-86400) { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
            return date
        }
        for format in ["h:mma", "ha"] {
            f.dateFormat = format
            guard let parsed = f.date(from: s) else { continue }
            let time = cal.dateComponents([.hour, .minute], from: parsed)
            return cal.nextDate(after: now.addingTimeInterval(-60), matching: time, matchingPolicy: .nextTime)
        }
        return nil
    }
}
