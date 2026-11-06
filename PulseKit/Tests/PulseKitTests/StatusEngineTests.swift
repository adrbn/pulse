import Foundation
import Testing
@testable import PulseKit

struct StatusEngineTests {
    let now = Fixtures.now

    func snap(_ edit: (inout Snapshot) -> Void = { _ in }) -> Snapshot {
        var s = Fixtures.snapshot()
        s.server.lastSeen = now
        edit(&s)
        return s
    }

    @Test func referenceDataIsHealthy() {
        // 1 stopped container does not change the status by default.
        let st = StatusEngine.evaluate(snap(), treatStoppedAsWarning: false, now: now)
        #expect(st.level == .healthy)
    }

    @Test func stoppedCountsWhenSettingIsOn() {
        let st = StatusEngine.evaluate(snap(), treatStoppedAsWarning: true, now: now)
        #expect(st.level == .warning)
        #expect(st.reasons == ["1 stopped"])
    }

    @Test func offlineAfterSixtySeconds() {
        let fresh = snap { $0.server.lastSeen = now.addingTimeInterval(-59) }
        let stale = snap { $0.server.lastSeen = now.addingTimeInterval(-61) }
        #expect(StatusEngine.evaluate(fresh, treatStoppedAsWarning: false, now: now).level == .healthy)
        #expect(StatusEngine.evaluate(stale, treatStoppedAsWarning: false, now: now).level == .offline)
    }

    @Test func unhealthyContainerWarns() {
        let s = snap { $0.containers[1].state = .unhealthy }
        #expect(StatusEngine.evaluate(s, treatStoppedAsWarning: false, now: now).level == .warning)
    }

    @Test("Thresholds are strict: at the line is fine, above it warns",
          arguments: [("ram", 90.0, false), ("ram", 90.5, true), ("disk", 85.0, false), ("disk", 86.0, true)])
    func metricThresholds(metric: String, value: Double, warns: Bool) {
        let s = snap { if metric == "ram" { $0.server.ram = value } else { $0.server.disk = value } }
        #expect((StatusEngine.evaluate(s, treatStoppedAsWarning: false, now: now).level == .warning) == warns)
    }

    @Test func temperatureAbove85Warns() {
        #expect(StatusEngine.evaluate(snap { $0.server.cpuTempC = 86 }, treatStoppedAsWarning: false, now: now).level == .warning)
        #expect(StatusEngine.evaluate(snap { $0.server.cpuTempC = 85 }, treatStoppedAsWarning: false, now: now).level == .healthy)
    }

    func cpuHistory(minutes: Int, value: Double) -> [Sample] {
        (0...minutes).map { Sample(time: now.addingTimeInterval(-Double(minutes - $0) * 60), cpu: value, ram: 40, disk: 60, temp: 60) }
    }

    @Test func cpuNeedsFiveSustainedMinutes() {
        let short = snap { $0.server.cpu = 95; $0.history = cpuHistory(minutes: 3, value: 95) }
        let long = snap { $0.server.cpu = 95; $0.history = cpuHistory(minutes: 5, value: 95) }
        var dip = cpuHistory(minutes: 5, value: 95); dip[2].cpu = 40
        let broken = snap { $0.server.cpu = 95; $0.history = dip }
        #expect(StatusEngine.evaluate(short, treatStoppedAsWarning: false, now: now).level == .healthy)
        #expect(StatusEngine.evaluate(long, treatStoppedAsWarning: false, now: now).level == .warning)
        #expect(StatusEngine.evaluate(broken, treatStoppedAsWarning: false, now: now).level == .healthy)
    }

    @Test func ringSeverity() {
        #expect(StatusEngine.severity(.cpu, value: 95, cpuSustained: false) == .normal)
        #expect(StatusEngine.severity(.cpu, value: 95, cpuSustained: true) == .warning)
        #expect(StatusEngine.severity(.cpu, value: 99, cpuSustained: false) == .critical)
        #expect(StatusEngine.severity(.ram, value: 92) == .warning)
        #expect(StatusEngine.severity(.ram, value: 96) == .critical)
        #expect(StatusEngine.severity(.disk, value: 61) == .normal)
        #expect(StatusEngine.severity(.disk, value: 90) == .warning)
        #expect(StatusEngine.severity(.disk, value: 96) == .critical)
    }
}

struct HaloMathTests {
    @Test func fortyThreeSlotsTileTheCircle() {
        let l = HaloLayout(count: 43, radius: 84)
        #expect(!l.isProportional)
        #expect(abs(l.slotLength * 43 - l.circumference) < 1e-9)
        #expect(abs(l.dashLength - (l.slotLength - 3)) < 1e-9)
        // Each gap is exactly 3 pt of arc.
        for i in 0..<42 {
            let gap = (l.slot(i + 1).start - l.slot(i).end) * l.circumference
            #expect(abs(gap - 3) < 1e-9)
        }
        // The last gap closes back at 12 o'clock.
        #expect(abs((1 - l.slot(42).end) * l.circumference - 3) < 1e-9)
    }

    @Test func slotZeroStartsAtTwelve() {
        let l = HaloLayout(count: 43, radius: 84)
        #expect(l.slot(0).start == 0)
        #expect(l.angle(0) > 0 && l.angle(0) < 2 * .pi / 43)
    }

    @Test func problemIndexFollowsAlphabeticalOrder() {
        let snap = Fixtures.snapshot()
        let i = try! #require(snap.containers.firstIndex { $0.name == "immich-ml" })
        // Alphabetical order keeps the slot stable whatever order the API returns.
        let shuffled = Snapshot(server: snap.server, containers: snap.containers.reversed(), updatedAt: snap.updatedAt)
        #expect(shuffled.containers.firstIndex { $0.name == "immich-ml" } == i)
        let l = HaloLayout(count: snap.total, radius: 84)
        let expected = (Double(i) + 0.5 - 1.5 / l.slotLength) / Double(snap.total)
        #expect(abs(l.center(i) - expected) < 1e-9)
    }

    @Test func proportionalAboveEighty() {
        #expect(!HaloLayout(count: 80, radius: 84).isProportional)
        #expect(HaloLayout(count: 81, radius: 84).isProportional)
    }

    @Test func emptyRingDoesNotDivideByZero() {
        let l = HaloLayout(count: 0, radius: 84)
        #expect(l.slotLength == 0 && l.dashLength == 0)
    }
}

@Test func singleContainerStacksFoldIntoOther() {
    let cs = [Container(name: "nc", stack: "nextcloud", state: .running), Container(name: "nc-db", stack: "nextcloud", state: .running),
              Container(name: "eli", stack: "eli", state: .running), Container(name: "bell", stack: "bell", state: .stopped)]
    let stacks = Stacks.group(cs)
    #expect(stacks.map(\.name) == ["other", "nextcloud"])   // "other" holds a stopped one, so it sorts first
    #expect(stacks.first?.containers.map(\.name) == ["bell", "eli"])

}

@Test func problemsLineCyclesThroughEveryName() {
    var s = Fixtures.snapshot()
    s.containers = Fixtures.containers(unhealthy: "jellyfin")
    let t = Date(timeIntervalSince1970: 0)
    let lines = Set((0..<s.problems.count).compactMap { WidgetText.problemsLine(s, now: t.addingTimeInterval(Double($0) * 3)) })
    #expect(s.problems.count == 2)
    #expect(lines.count == 2)
    #expect(lines.contains { $0.hasPrefix("jellyfin unhealthy") })
}
