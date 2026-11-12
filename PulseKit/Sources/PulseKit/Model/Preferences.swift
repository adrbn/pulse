import Foundation

public enum PulseStyle: String, CaseIterable, Codable, Sendable { case rings, halo, memory, live }
public enum ContainerRing: String, CaseIterable, Codable, Sendable { case segments, ticks, beads, inner }
public enum IconMode: String, CaseIterable, Codable, Sendable { case status, live }
public enum AppearanceMode: String, CaseIterable, Codable, Sendable { case system, light, dark }
public enum HaloCenter: String, CaseIterable, Codable, Sendable { case count, status, none }
public enum SourceKind: String, CaseIterable, Codable, Sendable { case beszel, direct }

public enum AppGroup {
    public static let id = "2TWQF4T93E.dev.adrbn.pulse"
    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
    public static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Pulse", isDirectory: true)
    }
}

/// Non-secret settings, shared with the widget through the App Group defaults.
/// Keys double as `@AppStorage` keys in the app.
public enum Pref {
    public static let style = "style"                    // PulseStyle
    public static let containerRing = "containerRing"    // ContainerRing
    public static let iconMode = "iconMode"              // IconMode
    public static let widgetsFollowStyle = "widgetsFollowStyle"
    public static let stoppedIsWarning = "stoppedIsWarning"
    public static let appearance = "appearance"          // AppearanceMode
    public static let desktopWidget = "desktopWidget"    // off | small | medium
    public static let haloCenter = "haloCenter"          // HaloCenter: container count, status glyph or nothing

    public static let source = "source"                  // SourceKind
    public static let displayName = "displayName"
    public static let beszelURL = "beszelURL"
    public static let beszelEmail = "beszelEmail"
    public static let beszelSystem = "beszelSystem"
    public static let dockerURL = "dockerURL"
    public static let proxmoxURL = "proxmoxURL"
    public static let proxmoxNode = "proxmoxNode"
    public static let proxmoxTokenID = "proxmoxTokenID"
    public static let proxmoxInsecure = "proxmoxInsecure"

    public static let alertOffline = "alertOffline"
    public static let alertUnhealthy = "alertUnhealthy"
    public static let alertStopped = "alertStopped"
    public static let alertBackOnline = "alertBackOnline"

    public static func registerDefaults(_ d: UserDefaults = AppGroup.defaults) {
        d.register(defaults: [
            style: PulseStyle.halo.rawValue,
            containerRing: ContainerRing.ticks.rawValue,
            iconMode: IconMode.status.rawValue,
            widgetsFollowStyle: true,
            stoppedIsWarning: false,
            appearance: AppearanceMode.system.rawValue,
            desktopWidget: "off",
            haloCenter: HaloCenter.count.rawValue,
            source: SourceKind.beszel.rawValue,
            displayName: "",
            beszelURL: "",
            dockerURL: "",
            proxmoxURL: "",
            proxmoxInsecure: false,
            alertOffline: true,
            alertUnhealthy: true,
            alertStopped: false,
            alertBackOnline: true,
        ])
    }
}

public extension UserDefaults {
    func value<E: RawRepresentable>(_ key: String, default def: E) -> E where E.RawValue == String {
        string(forKey: key).flatMap(E.init(rawValue:)) ?? def
    }
}
