import AppKit
import Foundation
import SMCKit

enum FanMode: String, Codable, CaseIterable, Identifiable {
    case auto = "Auto"
    case manual = "Manual"
    case curve = "Curve"
    var id: String { rawValue }
}

struct FanSetting: Codable, Equatable {
    var mode: FanMode = .auto
    var manualRPM: Double = 0
    var source: SensorGroup = .cpu
    /// Linear curve: at or below lowTemp the fan runs at its minimum, at or above highTemp at its maximum.
    var lowTemp: Double = 55
    var highTemp: Double = 90
}

enum HelperState: Equatable {
    case unknown
    case missing
    case outdated(String)
    case ready
}

@MainActor
final class Controller: ObservableObject {
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var temps: [TempReading] = []
    @Published private(set) var helperState: HelperState = .unknown
    @Published var lastError: String?
    @Published var settings: [FanSetting] {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
            applyAll()
        }
    }

    private static let settingsKey = "fanSettings"
    private let helper = HelperClient()
    private var timer: Timer?
    /// What fanctld was last told for each fan: nil = auto, value = rpm.
    private var sent: [Int: Double?] = [:]
    private var pinging = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode([FanSetting].self, from: data) {
            settings = saved
        } else {
            settings = []
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // fanctld also restores Auto when our socket closes; this just makes it immediate.
            MainActor.assumeIsolated { _ = self?.helper.sendSync("auto all") }
        }
    }

    var menuTitle: String {
        guard let t = hottest(.cpu) else { return "" }
        return "\(Int(t.rounded()))°"
    }

    func hottest(_ group: SensorGroup) -> Double? {
        temps.filter { $0.group == group }.map(\.value).max()
    }

    func curveRPM(fan: FanReading, setting: FanSetting) -> Double? {
        guard let t = hottest(setting.source) else { return nil }
        let span = max(setting.highTemp - setting.lowTemp, 1)
        let x = min(max((t - setting.lowTemp) / span, 0), 1)
        return fan.min + (fan.max - fan.min) * x
    }

    func refresh() {
        fans = Sensors.fans()
        temps = Sensors.temps()
        if settings.count < fans.count {
            settings += fans.dropFirst(settings.count).map { fan in
                // Default curve source: fan 0 follows the CPU, the rest follow the GPU.
                FanSetting(manualRPM: fan.min, source: fan.id == 0 ? .cpu : .gpu)
            }
        }
        if helperState != .ready { ping() } else { applyAll() }
    }

    func allAuto() {
        for i in settings.indices { settings[i].mode = .auto }
    }

    // MARK: Helper

    private func ping() {
        guard !pinging else { return }
        pinging = true
        helper.send("ping") { [weak self] reply in
            guard let self else { return }
            self.pinging = false
            guard let reply else {
                self.helperState = .missing
                return
            }
            let expected = "ok fanctld \(FanCtlProtocol.version)"
            self.helperState = reply == expected ? .ready : .outdated(reply)
            if self.helperState == .ready {
                self.sent = [:]
                self.applyAll()
            }
        }
    }

    private func applyAll() {
        guard helperState == .ready else { return }
        for fan in fans where fan.id < settings.count {
            let setting = settings[fan.id]
            let want: Double?
            switch setting.mode {
            case .auto: want = nil
            case .manual: want = min(max(setting.manualRPM, fan.min), fan.max)
            case .curve: want = curveRPM(fan: fan, setting: setting)
            }
            if let previous = sent[fan.id] {
                switch (previous, want) {
                case (nil, nil): continue
                case let (p?, w?) where abs(p - w) < 25: continue
                default: break
                }
            }
            sent[fan.id] = .some(want)
            let command = want.map { "set \(fan.id) \(Int($0))" } ?? "auto \(fan.id)"
            helper.send(command) { [weak self] reply in
                guard let self else { return }
                if reply == nil {
                    self.helperState = .missing
                    self.sent = [:]
                } else if let reply, reply.hasPrefix("err") {
                    self.lastError = reply
                    self.sent[fan.id] = nil
                } else {
                    self.lastError = nil
                }
            }
        }
    }

    func installHelper() {
        runPrivileged(script: "install-helper.sh")
    }

    func uninstallHelper() {
        runPrivileged(script: "uninstall-helper.sh")
    }

    private func runPrivileged(script: String) {
        guard let resources = Bundle.main.resourcePath else { return }
        let source = """
        do shell script "/bin/sh " & quoted form of "\(resources)/\(script)" & " " & \
        quoted form of "\(resources)" & " \(getuid())" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {  // -128 = user cancelled
            lastError = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
        }
        helper.disconnect()
        helperState = .unknown
        sent = [:]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.ping() }
    }
}
