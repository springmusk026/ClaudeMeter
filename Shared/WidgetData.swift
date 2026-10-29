import Foundation

/// What the widget shows, written by the app to a file the widget may read.
/// The widget runs sandboxed and can't read Claude Code's files itself.
struct WidgetData: Codable, Equatable {
    struct Gauge: Codable, Equatable {
        var percent: Double
        var resets: Date
    }

    struct NamedGauge: Codable, Equatable {
        var name: String
        var gauge: Gauge
    }

    var account: String?          // set when there are several accounts
    var plan: String?
    var fiveHour: Gauge?
    var weekly: Gauge?
    var models: [NamedGauge] = []
    var todayCost: Double = 0
    var todayTokens: Int = 0
    var limitAt: Date?            // when the 5-hour limit is reached at the current pace
    var working = false
    var warn: Double = 80
    var critical: Double = 95
    var updated: Date

    /// ~/Library/Application Support/ClaudeMeter/widget.json in the real home folder
    /// (inside the sandbox, the home directory APIs point at the widget's container).
    static var url: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/ClaudeMeter/widget.json")
    }

    static func load() -> WidgetData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetData.self, from: data)
    }

    /// Writes the file; returns true when its contents changed.
    @discardableResult
    func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return false }
        if let old = try? Data(contentsOf: Self.url), old == data { return false }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: Self.url, options: .atomic)) != nil
    }

    func level(_ percent: Double) -> Level {
        percent >= critical ? .critical : percent >= warn ? .caution : .normal
    }

    enum Level { case normal, caution, critical }
}
