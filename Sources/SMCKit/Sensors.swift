import Foundation

public enum FanCtlProtocol {
    public static let socketPath = "/var/run/fanctld.sock"
    public static let helperLabel = "local.fanctl.daemon"
    /// Bump when the socket protocol changes so the app can ask for a helper reinstall.
    public static let version = "1"
}

public struct FanReading: Equatable {
    public let id: Int
    public let actual: Double
    public let min: Double
    public let max: Double
    public let target: Double
    public let manual: Bool
}

public enum SensorGroup: String, CaseIterable, Codable {
    case cpu = "CPU"
    case gpu = "GPU"
}

public struct TempReading: Equatable, Identifiable {
    public let key: String
    public let label: String
    public let group: SensorGroup
    public let value: Double
    public var id: String { key }
}

public enum Sensors {
    /// Candidate temperature keys, most useful first; only those present are reported.
    static let tempKeys: [(key: String, label: String, group: SensorGroup)] = [
        ("TCXC", "CPU die", .cpu),
        ("TC0D", "CPU die", .cpu),
        ("TC0E", "CPU die", .cpu),
        ("TC0P", "CPU proximity", .cpu),
        ("TGDD", "GPU die", .gpu),
        ("TG0D", "GPU die", .gpu),
        ("TG0P", "GPU proximity", .gpu),
    ]

    public static func fanCount() -> Int {
        Int(SMC.shared.readDouble("FNum") ?? 0)
    }

    public static func fans() -> [FanReading] {
        let smc = SMC.shared
        return (0..<fanCount()).map { i in
            FanReading(
                id: i,
                actual: smc.readDouble("F\(i)Ac") ?? 0,
                min: smc.readDouble("F\(i)Mn") ?? 0,
                max: smc.readDouble("F\(i)Mx") ?? 0,
                target: smc.readDouble("F\(i)Tg") ?? 0,
                manual: (smc.readDouble("F\(i)Md") ?? 0) == 1
            )
        }
    }

    public static func temps() -> [TempReading] {
        var seenLabels = Set<String>()
        return tempKeys.compactMap { entry in
            guard let v = SMC.shared.readDouble(entry.key), v > 0, v < 130,
                  seenLabels.insert(entry.label).inserted else { return nil }
            return TempReading(key: entry.key, label: entry.label, group: entry.group, value: v)
        }
    }
}
