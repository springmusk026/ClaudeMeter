import SwiftUI

// MARK: - Pricing (USD per million tokens, Anthropic API list prices, Oct 2026)

struct Rate { let input: Double; let output: Double; let cacheRead: Double }

// First match wins, so more specific names come first.
let rates: [(String, Rate)] = [
    ("fable",    Rate(input: 10,  output: 50,  cacheRead: 0.25)),
    ("mythos",   Rate(input: 10,  output: 50,  cacheRead: 0.25)),
    ("opus-5-5", Rate(input: 4,   output: 20,  cacheRead: 0.20)),
    ("opus-5",   Rate(input: 5,   output: 25,  cacheRead: 0.50)),
    ("opus-4-8", Rate(input: 5,   output: 25,  cacheRead: 0.50)),
    ("opus-4-7", Rate(input: 5,   output: 25,  cacheRead: 0.50)),
    ("opus-4-6", Rate(input: 5,   output: 25,  cacheRead: 0.50)),
    ("opus-4-5", Rate(input: 5,   output: 25,  cacheRead: 0.50)),
    ("opus-4",   Rate(input: 15,  output: 75,  cacheRead: 1.50)),
    ("sonnet-5", Rate(input: 2,   output: 10,  cacheRead: 0.20)),
    ("sonnet-4", Rate(input: 3,   output: 15,  cacheRead: 0.30)),
    ("haiku-5",  Rate(input: 0.1, output: 0.5, cacheRead: 0.01)),
    ("haiku-4",  Rate(input: 1,   output: 5,   cacheRead: 0.10)),
]

func rate(for model: String) -> Rate? { rates.first { model.contains($0.0) }?.1 }

// MARK: - Usage records

/// One API response logged by Claude Code.
struct Entry {
    let date: Date
    let model: String
    let project: String
    let session: String
    let account: String
    let input, output, cacheRead, cacheWrite5m, cacheWrite1h: Int

    // Cache writes cost 1.25x input (5 min) or 2x input (1 hour)
    var cost: Double {
        guard let r = rate(for: model) else { return 0 }
        let sum = Double(input) * r.input + Double(output) * r.output
            + Double(cacheRead) * r.cacheRead
            + Double(cacheWrite5m) * r.input * 1.25 + Double(cacheWrite1h) * r.input * 2
        return sum / 1_000_000
    }
}

struct Bucket {
    var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    var cost = 0.0
    var messages = 0

    var tokens: Int { input + output + cacheRead + cacheWrite }

    /// Share of prompt tokens served from cache (billed at ~10% of input price).
    var cacheReuse: Double {
        let prompt = input + cacheRead + cacheWrite
        return prompt == 0 ? 0 : Double(cacheRead) / Double(prompt)
    }

    mutating func add(_ e: Entry) {
        input += e.input
        output += e.output
        cacheRead += e.cacheRead
        cacheWrite += e.cacheWrite5m + e.cacheWrite1h
        cost += e.cost
        messages += 1
    }

    mutating func merge(_ b: Bucket) {
        input += b.input
        output += b.output
        cacheRead += b.cacheRead
        cacheWrite += b.cacheWrite
        cost += b.cost
        messages += b.messages
    }
}

// MARK: - Model names and colors

/// "claude-opus-5-5" -> "Opus 5.5", "claude-3-5-sonnet-20241022" -> "Sonnet 3.5"
func modelName(_ id: String) -> String {
    let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
    guard let family = parts.first(where: { Int($0) == nil }) else { return id }
    let version = parts.filter { $0.count <= 2 && Int($0) != nil }.joined(separator: ".")
    return family.capitalized + (version.isEmpty ? "" : " \(version)")
}

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
