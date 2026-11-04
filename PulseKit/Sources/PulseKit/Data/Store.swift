import Foundation

/// JSON files in the App Group container: the latest snapshot (read by widgets)
/// and the 7-day sample/event history (owned by the app).
public enum Store {
    public static let keepHistory: TimeInterval = 7 * 86400

    public struct History: Codable, Sendable {
        public var samples: [Sample] = []
        public var events: [PulseEvent] = []
        public init() {}
    }

    static func url(_ name: String, in dir: URL) -> URL { dir.appendingPathComponent(name) }

    public static func loadSnapshot(dir: URL = AppGroup.container) -> Snapshot? {
        read(Snapshot.self, url("snapshot.json", in: dir))
    }

    public static func save(_ snap: Snapshot, dir: URL = AppGroup.container) {
        write(snap, url("snapshot.json", in: dir))
    }

    public static func loadHistory(dir: URL = AppGroup.container) -> History {
        read(History.self, url("history.json", in: dir)) ?? History()
    }

    public static func save(_ history: History, dir: URL = AppGroup.container) {
        write(history, url("history.json", in: dir))
    }

    /// Adds one sample per minute at most and drops anything older than 7 days.
    public static func appending(_ sample: Sample, to history: History) -> History {
        var h = history
        if let last = h.samples.last, sample.time.timeIntervalSince(last.time) < 60 { return h }
        h.samples.append(sample)
        let cutoff = sample.time.addingTimeInterval(-keepHistory)
        h.samples.removeAll { $0.time < cutoff }
        h.events.removeAll { $0.time < cutoff }
        return h
    }

    static func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(T.self, from: d)
    }

    static func write<T: Encodable>(_ value: T, _ url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Pulse: could not write \(url.lastPathComponent): \(error)")
        }
    }
}
