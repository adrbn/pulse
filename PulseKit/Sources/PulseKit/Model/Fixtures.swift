import Foundation

/// Reference data from the design (homelab at 14:35) for previews, snapshots and tests.
public enum Fixtures {
    public static var now: Date {
        Calendar.current.date(bySettingHour: 14, minute: 35, second: 0, of: Date(timeIntervalSince1970: 1_793_750_400)) ?? .now
    }

    static let stacks: [(String, [String])] = [
        ("immich", ["immich-ml", "immich-postgres", "immich-redis", "immich-server"]),
        ("media", ["audiobookshelf", "jellyfin", "lidarr", "navidrome", "prowlarr", "qbittorrent", "radarr", "sonarr"]),
        ("home", ["esphome", "home-assistant", "mosquitto", "node-red", "scrypted", "zigbee2mqtt"]),
        ("files & backup", ["backrest", "filebrowser", "nextcloud", "nextcloud-db", "nextcloud-redis", "syncthing"]),
        ("monitoring", ["beszel", "beszel-agent", "dozzle", "grafana", "prometheus", "uptime-kuma"]),
        ("network", ["adguardhome", "caddy", "tailscale", "traefik", "wireguard"]),
        ("dev", ["code-server", "forgejo", "forgejo-db", "n8n"]),
        ("other", ["homepage", "kiwix", "miniflux", "vaultwarden"]),
    ]

    static let cpu: [String: Double] = [
        "jellyfin": 4.6, "home-assistant": 2.1, "immich-server": 1.2, "nextcloud": 0.9, "traefik": 0.3,
    ]

    public static func containers(now: Date = now, unhealthy: String? = nil) -> [Container] {
        stacks.flatMap { stack, names in
            names.map { name in
                if name == "immich-ml" {
                    return Container(name: name, image: "ghcr.io/immich-app/immich-machine-learning", stack: stack,
                                     state: .stopped, exitCode: 137, stoppedAt: now.addingTimeInterval(-2 * 3600 - 4 * 60))
                }
                let health: ContainerHealth = ["nextcloud", "vaultwarden"].contains(name) ? .healthy : .none
                if name == unhealthy {
                    return Container(name: name, stack: stack, state: .unhealthy, health: .unhealthy, cpu: 0.4, memBytes: 2e8)
                }
                return Container(name: name, image: name, stack: stack, state: .running, health: health,
                                 cpu: cpu[name] ?? 0.1, memBytes: 1.5e8)
            }
        }
    }

    public static func history(now: Date = now) -> [Sample] {
        let start = now.addingTimeInterval(-24 * 3600)
        let cal = Calendar.current
        let spike = cal.date(bySettingHour: 3, minute: 10, second: 0, of: now) ?? now
        return (0..<1440).map { i in
            let t = start.addingTimeInterval(Double(i) * 60)
            let wave = 9 + 3 * sin(Double(i) / 90) + Double((i * 7919) % 5) * 0.4
            let dt = t.timeIntervalSince(spike)
            let cpu = dt >= 0 && dt < 14 * 60 ? 71 - abs(dt / 60 - 3) * 2.5 : wave
            let ram = dt >= 0 && dt < 14 * 60 ? 63 : 46 + 2 * sin(Double(i) / 200)
            let temp = dt >= 0 && dt < 14 * 60 ? 78 : 62 + 3 * sin(Double(i) / 120)
            return Sample(time: t, cpu: cpu, ram: ram, disk: 60.6 + Double(i) / 1440 * 0.4, temp: temp)
        }
    }

    public static func events(now: Date = now) -> [PulseEvent] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now }
        return [
            PulseEvent(id: "exit-immich-ml", time: at(12, 31), text: "immich-ml exited (137)", kind: .exited, container: "immich-ml"),
            PulseEvent(id: "boot", time: at(10, 29), text: "homelab booted, 43 containers up", kind: .boot),
            PulseEvent(id: "spike", time: at(3, 10), text: "backrest run, CPU 71% for 14 min", kind: .cpuSpike),
        ]
    }

    public static func snapshot(_ level: StatusLevel = .healthy) -> Snapshot {
        let n = now
        let server = Server(name: "homelab", cpuModel: "Intel N150", cores: 4, online: level != .offline,
                            lastSeen: level == .offline ? n.addingTimeInterval(-180) : n.addingTimeInterval(-5),
                            uptime: 4 * 3600 + 6 * 60, cpu: 12, ram: 48, disk: 61, cpuTempC: 65,
                            load1: 0.84, load5: 1.02, load15: 0.97, netInBps: 2_400_000, netOutBps: 310_000)
        let netIn = (0..<12).map { 2_000_000 + 600_000 * sin(Double($0) * 1.3) + Double($0 % 3) * 150_000 }
        let netOut = (0..<12).map { 300_000 + 60_000 * sin(Double($0) * 1.7 + 1) }
        return Snapshot(server: server, containers: containers(now: n, unhealthy: level == .warning ? "nextcloud" : nil),
                        netIn: netIn, netOut: netOut, history: history(now: n), events: events(now: n),
                        updatedAt: n.addingTimeInterval(-5), canStart: true)
    }
}
