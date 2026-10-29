import Foundation

// MARK: - Formatting

func fmtTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
    case 1_000_000...:     return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...:         return String(format: "%.0fk", Double(n) / 1e3)
    default:               return "\(n)"
    }
}

func fmtCost(_ c: Double) -> String {
    if c > 0 && c < 0.01 { return "<$0.01" }
    return String(format: c >= 100 ? "$%.0f" : "$%.2f", c)
}

func fmtDuration(_ t: TimeInterval) -> String {
    let m = max(0, Int(t) / 60)
    return m >= 60 ? "\(m / 60)h " + String(format: "%02dm", m % 60) : "\(m)m"
}

func fmtPercent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

func dayStamp(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
