import Foundation
import CoreServices

/// Reads Claude Code's JSONL logs incrementally: each file is only read from
/// where the previous pass stopped, so refreshes stay cheap as logs grow.
final class LogReader {
    private struct FileState {
        var offset: UInt64 = 0
        var items: [(key: String, entry: Entry)] = []
    }

    private var files: [String: FileState] = [:]
    private let marker = Data("\"type\":\"assistant\"".utf8)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Every account's entries, oldest first.
    func load(_ accounts: [Account]) -> [Entry] {
        var live = Set<String>()
        var seen = Set<String>()
        var all: [Entry] = []
        for account in accounts {
            guard let walker = FileManager.default.enumerator(
                at: account.projects, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            read(walker, account: account.id, live: &live, seen: &seen, into: &all)
        }
        files = files.filter { live.contains($0.key) }
        return all.sorted { $0.date < $1.date }
    }

    private func read(_ walker: FileManager.DirectoryEnumerator, account: String,
                      live: inout Set<String>, seen: inout Set<String>, into all: inout [Entry]) {
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let path = url.path
            live.insert(path)
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

            var state = files[path] ?? FileState()
            if size < state.offset { state = FileState() }  // file was rewritten
            if size > state.offset { readNewLines(url, account: account, into: &state) }
            files[path] = state

            // The same API response can be logged more than once; count it once
            for item in state.items where seen.insert(item.key).inserted { all.append(item.entry) }
        }
    }

    private func readNewLines(_ url: URL, account: String, into state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: state.offset)
        // Stop at the last newline so a line still being written is read next time
        guard let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }

        let chunk = data[data.startIndex...lastNewline]
        state.offset += UInt64(chunk.count)
        for line in chunk.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            if let item = parse(line, file: url, account: account) { state.items.append(item) }
        }
    }

    private func parse(_ line: Data, file: URL, account: String) -> (key: String, entry: Entry)? {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let date = iso.date(from: ts),
              let model = msg["model"] as? String, model != "<synthetic>"
        else { return nil }

        func num(_ dict: [String: Any]?, _ key: String) -> Int { (dict?[key] as? NSNumber)?.intValue ?? 0 }
        let split = usage["cache_creation"] as? [String: Any]
        let write5m = split != nil ? num(split, "ephemeral_5m_input_tokens")
                                   : num(usage, "cache_creation_input_tokens")
        let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? file.deletingLastPathComponent().lastPathComponent
        let session = obj["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent
        let key = "\(msg["id"] as? String ?? UUID().uuidString):\(obj["requestId"] as? String ?? "")"

        return (key, Entry(
            date: date, model: model, project: project, session: session, account: account,
            input: num(usage, "input_tokens"), output: num(usage, "output_tokens"),
            cacheRead: num(usage, "cache_read_input_tokens"),
            cacheWrite5m: write5m, cacheWrite1h: num(split, "ephemeral_1h_input_tokens")))
    }
}

/// Calls `onChange` (on the main queue) whenever anything under `paths` changes.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        // 1 s latency coalesces the burst of writes Claude Code makes per message
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
