import Foundation

/// Turns successive readings into the "Today" timeline: container exits, health changes,
/// boots and sustained CPU spikes (> 60 % for > 5 min).
public enum EventDetector {
    public static let spikeLevel = 60.0
    public static let spikeMinDuration: TimeInterval = 5 * 60

    public static func detect(previous: [Container]?, current: Reading, samples: [Sample],
                              existing: [PulseEvent], now: Date) -> [PulseEvent] {
        var out: [PulseEvent] = []
        let before = Dictionary((previous ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        for c in current.containers {
            let old = before[c.name]
            if c.state == .stopped, previous == nil || old?.state != .stopped {
                let t = c.stoppedAt ?? now
                // On first launch only keep exits from the last day.
                if previous != nil || now.timeIntervalSince(t) < 86400 {
                    let code = c.exitCode.map { " (\($0))" } ?? ""
                    out.append(PulseEvent(id: "exit-\(c.name)-\(Int(t.timeIntervalSince1970))", time: t,
                                          text: "\(c.name) exited\(code)", kind: .exited, container: c.name))
                }
            }
            if c.state == .unhealthy, let old, old.state != .unhealthy {
                out.append(PulseEvent(id: "unhealthy-\(c.name)-\(Int(now.timeIntervalSince1970))", time: now,
                                      text: "\(c.name) unhealthy", kind: .unhealthy, container: c.name))
            }
        }

        let s = current.server
        if s.online, s.uptime > 0 {
            let boot = now.addingTimeInterval(-s.uptime)
            let known = existing.contains { $0.kind == .boot && abs($0.time.timeIntervalSince(boot)) < 300 }
            if !known, now.timeIntervalSince(boot) < Store.keepHistory {
                let n = current.containers.filter(\.isRunning).count
                out.append(PulseEvent(id: "boot-\(Int(boot.timeIntervalSince1970))", time: boot,
                                      text: "\(s.name) booted, \(n) containers up", kind: .boot))
            }
        }

        let top = current.containers.max { $0.cpu < $1.cpu }?.name
        for run in spikes(samples) {
            let id = "spike-\(Int(run.start.timeIntervalSince1970))"
            let prior = existing.first { $0.id == id }
            // Keep the container name captured when the spike was first seen.
            let who = prior?.container ?? (now.timeIntervalSince(run.end) < 120 ? top : nil)
            let mins = Int((run.end.timeIntervalSince(run.start) / 60).rounded()) + 1
            let text = (who.map { "\($0) busy, " } ?? "") + "CPU \(Int(run.peak.rounded()))% for \(mins) min"
            out.append(PulseEvent(id: id, time: run.start, text: text, kind: .cpuSpike, container: who))
        }
        return out
    }

    public struct Spike: Equatable { public var start: Date; public var end: Date; public var peak: Double }

    /// Contiguous runs of samples above 60 % lasting at least 5 minutes.
    public static func spikes(_ samples: [Sample]) -> [Spike] {
        var runs: [Spike] = []
        var cur: Spike?
        for s in samples {
            if s.cpu > spikeLevel {
                if var c = cur, s.time.timeIntervalSince(c.end) <= 120 {
                    c.end = s.time; c.peak = max(c.peak, s.cpu); cur = c
                } else {
                    if let c = cur { runs.append(c) }
                    cur = Spike(start: s.time, end: s.time, peak: s.cpu)
                }
            } else if let c = cur {
                runs.append(c); cur = nil
            }
        }
        if let c = cur { runs.append(c) }
        return runs.filter { $0.end.timeIntervalSince($0.start) >= spikeMinDuration - 60 }
    }

    /// Merge by id (new wins), newest first.
    public static func merge(_ old: [PulseEvent], _ new: [PulseEvent]) -> [PulseEvent] {
        var byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        new.forEach { byID[$0.id] = $0 }
        return byID.values.sorted { $0.time > $1.time }
    }
}
