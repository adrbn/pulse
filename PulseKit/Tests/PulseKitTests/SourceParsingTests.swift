import Foundation
import Testing
@testable import PulseKit

/// Fixtures are real responses from the homelab Beszel hub (0.21) and Docker proxy.
struct SourceParsingTests {
    func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    @Test func beszelSystemMapsToServer() throws {
        let sys = try fixture("beszel_systems", as: BeszelSource.List<BeszelSource.System>.self).items[0]
        let det = try fixture("beszel_details", as: BeszelSource.List<BeszelSource.Details>.self).items[0]
        let st = try fixture("beszel_stats", as: BeszelSource.List<BeszelSource.Stats>.self).items[0]
        let now = Date()
        let s = BeszelSource.server(sys, details: det, bandwidth: st.stats.b, displayName: "homelab", now: now)
        #expect(s.name == "homelab")
        #expect(s.cpuModel == "Intel N150")
        #expect(s.cores == 4)
        #expect(s.online && s.lastSeen == now)
        #expect(s.uptime == 18570)
        #expect(s.cpu == 12.96 && s.ram == 50.47 && s.disk == 72.43)
        #expect(s.cpuTempC == 55)
        #expect(s.load1 == 0.72 && s.load15 == 0.77)
        #expect(s.netOutBps == 8402 && s.netInBps == 26489)
    }

    @Test func beszelNameFallsBackToHub() throws {
        let sys = try fixture("beszel_systems", as: BeszelSource.List<BeszelSource.System>.self).items[0]
        #expect(BeszelSource.server(sys, details: nil, bandwidth: nil, displayName: "", now: .now).name == "hömelab")
        #expect(BeszelSource.server(sys, details: nil, bandwidth: nil, displayName: nil, now: .now).cores == 4)
    }

    @Test func beszelContainersMapHealth() throws {
        let items = try fixture("beszel_containers", as: BeszelSource.List<BeszelSource.BContainer>.self).items
        let c = BeszelSource.containers(items)
        #expect(c.map(\.state) == [.running, .running, .unhealthy])
        #expect(c.map(\.health) == [.none, .healthy, .unhealthy])
        #expect(abs(c[0].memBytes - 364.98 * 1_048_576) < 1)
    }

    @Test func dockerMapsStateExitCodeAndStack() throws {
        let items = try fixture("docker_containers", as: [DockerClient.Item].self)
        let c = Dictionary(uniqueKeysWithValues: DockerClient.map(items).map { ($0.name, $0) })
        let collabora = try #require(c["collabora"])
        #expect(collabora.state == .stopped)
        #expect(collabora.exitCode == 137)
        #expect(collabora.stack == "nextcloud")
        #expect(c["freshrss"]?.health == .healthy)
        #expect(c["n8n"]?.state == .running)
        #expect(c["sillabus"]?.stack == "other")   // no compose label
    }

    @Test func mergeKeepsDockerStateAndBeszelUsage() {
        let docker = [Container(name: "a", stack: "s", state: .stopped, exitCode: 1), Container(name: "b", state: .running)]
        let beszel = [Container(name: "b", state: .running, cpu: 3, memBytes: 9)]
        let m = BeszelSource.merge(docker: docker, beszel: beszel)
        #expect(m[0].state == .stopped && m[0].stack == "s")
        #expect(m[1].cpu == 3 && m[1].memBytes == 9)
    }

    @Test func exitCodeParsing() {
        #expect(DockerClient.exitCode("Exited (137) 5 hours ago") == 137)
        #expect(DockerClient.exitCode("Exited (0) 2 days ago") == 0)
        #expect(DockerClient.exitCode("Up 5 hours") == nil)
    }

    @Test func pocketBaseAndDockerDates() {
        #expect(Dates.parse("2026-11-04 14:46:36.319Z") != nil)
        #expect(Dates.parse("2026-11-04T09:45:34.70297528Z") != nil)
        #expect(Dates.parse("2026-11-04T09:45:34Z") != nil)
    }
}

struct EventTests {
    let now = Fixtures.now

    func reading(_ containers: [Container], uptime: TimeInterval = 4 * 3600) -> Reading {
        var s = Fixtures.snapshot().server
        s.uptime = uptime
        return Reading(server: s, containers: containers, canStart: true)
    }

    @Test func containerExitBecomesEvent() {
        let before = [Container(name: "web", state: .running)]
        let after = [Container(name: "web", state: .stopped, exitCode: 1, stoppedAt: now)]
        let ev = EventDetector.detect(previous: before, current: reading(after), samples: [], existing: [], now: now)
        #expect(ev.contains { $0.kind == .exited && $0.text == "web exited (1)" })
    }

    @Test func bootIsRecordedOnce() {
        let r = reading([Container(name: "web", state: .running)])
        let first = EventDetector.detect(previous: nil, current: r, samples: [], existing: [], now: now)
        let boot = first.filter { $0.kind == .boot }
        #expect(boot.count == 1 && boot[0].text == "homelab booted, 1 containers up")
        let again = EventDetector.detect(previous: [], current: r, samples: [], existing: first, now: now.addingTimeInterval(30))
        #expect(!again.contains { $0.kind == .boot })
    }

    @Test func spikesNeedFiveMinutesAboveSixty() {
        let samples = Fixtures.history()
        let runs = EventDetector.spikes(samples)
        #expect(runs.count == 1)
        #expect(Int(runs[0].peak.rounded()) == 71)
        #expect(EventDetector.spikes(Array(samples.prefix(10))).isEmpty)
    }

    @Test func historyKeepsOneSamplePerMinute() {
        var h = Store.History()
        h = Store.appending(Sample(time: now, cpu: 1, ram: 1, disk: 1, temp: nil), to: h)
        h = Store.appending(Sample(time: now.addingTimeInterval(30), cpu: 1, ram: 1, disk: 1, temp: nil), to: h)
        h = Store.appending(Sample(time: now.addingTimeInterval(61), cpu: 1, ram: 1, disk: 1, temp: nil), to: h)
        #expect(h.samples.count == 2)
        h = Store.appending(Sample(time: now.addingTimeInterval(8 * 86400), cpu: 1, ram: 1, disk: 1, temp: nil), to: h)
        #expect(h.samples.count == 1)
    }
}

/// `PULSE_LIVE_DOCKER=http://your-server:8772 swift test --filter LiveDocker`
@Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_LIVE_DOCKER"] != nil))
func liveDocker() async throws {
    let url = try #require(URL(string: ProcessInfo.processInfo.environment["PULSE_LIVE_DOCKER"] ?? ""))
    let list = try await DockerClient(base: url).containers()
    #expect(list.count > 10)
    print("live docker:", list.count, "containers,", list.filter { $0.state != .running }.map(\.name))
}
