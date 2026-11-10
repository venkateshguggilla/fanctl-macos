import SwiftUI
import SMCKit

@main
struct FanCtlApp: App {
    @StateObject private var controller = Controller()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "fan")
            Text(controller.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FanCtl").font(.headline)
                Spacer()
                helperBadge
            }

            temperatures

            ForEach(controller.fans, id: \.id) { fan in
                if fan.id < controller.settings.count {
                    FanCard(fan: fan, setting: $controller.settings[fan.id])
                }
            }

            if let error = controller.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            helperBanner

            Divider()
            HStack {
                Button("All Auto") { controller.allAuto() }
                Spacer()
                Menu("Helper") {
                    Button("Install / Reinstall…") { controller.installHelper() }
                    Button("Uninstall…") { controller.uninstallHelper() }
                }
                .fixedSize()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var helperBadge: some View {
        let (color, text): (Color, String) = {
            switch controller.helperState {
            case .ready: return (.green, "Helper ready")
            case .unknown: return (.gray, "Checking…")
            case .missing: return (.orange, "Read-only")
            case .outdated: return (.orange, "Helper outdated")
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var helperBanner: some View {
        switch controller.helperState {
        case .missing, .outdated:
            VStack(alignment: .leading, spacing: 6) {
                Text(controller.helperState == .missing
                     ? "Changing fan speed needs the FanCtl helper, which runs as root. Install it once with your admin password."
                     : "The installed helper doesn't match this app. Reinstall it.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Install Helper…") { controller.installHelper() }
            }
            .padding(8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        default:
            EmptyView()
        }
    }

    private var temperatures: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(controller.temps) { t in
                GridRow {
                    Text(t.label).foregroundStyle(.secondary)
                    Text(String(format: "%.1f °C", t.value)).monospacedDigit()
                }
            }
        }
        .font(.callout)
    }
}

struct FanCard: View {
    @EnvironmentObject var controller: Controller
    let fan: FanReading
    @Binding var setting: FanSetting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fan \(fan.id)").bold()
                Spacer()
                Text("\(Int(fan.actual)) rpm").monospacedDigit()
                Text(fan.manual ? "forced" : "auto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(fan.actual - fan.min, fan.max - fan.min)),
                         total: max(fan.max - fan.min, 1))

            Picker("", selection: $setting.mode) {
                ForEach(FanMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch setting.mode {
            case .auto:
                Text("System controls this fan (\(Int(fan.min))–\(Int(fan.max)) rpm).")
                    .font(.caption).foregroundStyle(.secondary)
            case .manual:
                HStack {
                    Slider(value: $setting.manualRPM, in: fan.min...max(fan.max, fan.min + 1), step: 50)
                    Text("\(Int(setting.manualRPM))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            case .curve:
                curveControls
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var curveControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Follow", selection: $setting.source) {
                ForEach(SensorGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Min speed at \(Int(setting.lowTemp)) °C",
                    value: $setting.lowTemp, in: 30...(setting.highTemp - 5), step: 5)
            Stepper("Max speed at \(Int(setting.highTemp)) °C",
                    value: $setting.highTemp, in: (setting.lowTemp + 5)...100, step: 5)
            if let t = controller.hottest(setting.source),
               let rpm = controller.curveRPM(fan: fan, setting: setting) {
                Text("\(setting.source.rawValue) \(Int(t)) °C → \(Int(rpm)) rpm")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}
