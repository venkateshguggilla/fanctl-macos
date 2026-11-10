// fanctld: root helper that owns all SMC writes.
//
// Line protocol over a Unix socket (one reply line per command):
//   ping            -> ok fanctld <version>
//   set <fan> <rpm> -> ok <clamped rpm> | err <message>
//   auto <fan|all>  -> ok
//
// Safety: speeds are clamped to the firmware F<n>Mn/F<n>Mx range, a fan returns
// to Auto when the client that set it disconnects, and every fan returns to Auto
// on startup and on SIGTERM/SIGINT/SIGHUP.

import Foundation
import SMCKit

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

func log(_ message: String) {
    print("[fanctld] \(message)")
}

let smc = SMC.shared
guard smc.isOpen else {
    log("cannot open AppleSMC")
    exit(1)
}

let args = CommandLine.arguments

if args.contains("--probe") {
    for f in Sensors.fans() {
        print("fan \(f.id): \(Int(f.actual)) rpm (min \(Int(f.min)), max \(Int(f.max)), target \(Int(f.target)), \(f.manual ? "manual" : "auto"))")
    }
    for t in Sensors.temps() {
        print("\(t.key) \(t.label): \(String(format: "%.1f", t.value)) C")
    }
    print("Ftst key present: \(smc.has("Ftst"))")
    print("Apple Silicon-style sensors: \(Sensors.discoveredTemps().map { "\($0.label) \(String(format: "%.1f", $0.value)) C" })")
    exit(0)
}

var ownerUID: uid_t?
if let i = args.firstIndex(of: "--owner-uid"), i + 1 < args.count, let uid = UInt32(args[i + 1]) {
    ownerUID = uid
}
let socketPath = args.firstIndex(of: "--socket").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    ?? FanCtlProtocol.socketPath

final class FanControl {
    let count = Sensors.fanCount()
    private let lock = NSLock()
    private var desired: [Int: Double] = [:]  // fan -> rpm while under manual control
    private var owners: [Int: Int] = [:]      // fan -> client id that set it
    private var usedFtst = false

    func setManual(fan: Int, rpm: Double, client: Int) throws -> Double {
        lock.lock(); defer { lock.unlock() }
        guard (0..<count).contains(fan) else { throw Failure("no fan \(fan)") }
        let lo = smc.readDouble("F\(fan)Mn") ?? 0
        let hi = smc.readDouble("F\(fan)Mx") ?? 0
        guard hi > lo else { throw Failure("fan \(fan) has no valid range") }
        let value = min(max(rpm, lo), hi)
        try apply(fan: fan, rpm: value)
        desired[fan] = value
        owners[fan] = client
        return value
    }

    func setAuto(fan: Int) {
        lock.lock(); defer { lock.unlock() }
        restore(fan)
    }

    func restoreAll() {
        lock.lock(); defer { lock.unlock() }
        for fan in 0..<count { restore(fan) }
    }

    func clientGone(_ client: Int) {
        lock.lock(); defer { lock.unlock() }
        for (fan, owner) in owners where owner == client { restore(fan) }
    }

    /// Firmware can drop a fan back to Auto on its own (e.g. after sleep); put it back.
    func reassert() {
        lock.lock(); defer { lock.unlock() }
        for (fan, rpm) in desired {
            let manual = smc.readDouble("F\(fan)Md") == 1
            let target = smc.readDouble("F\(fan)Tg") ?? 0
            if !manual || abs(target - rpm) > 1 {
                do { try apply(fan: fan, rpm: rpm) } catch { log("reassert fan \(fan): \(error)") }
            }
        }
    }

    private func apply(fan: Int, rpm: Double) throws {
        let modeKey = "F\(fan)Md"
        if smc.readDouble(modeKey) != 1 {
            let accepted = (try? smc.write(modeKey, 1)) != nil && smc.readDouble(modeKey) == 1
            if !accepted {
                // Apple Silicon: F<n>Md is refused until the test-mode key Ftst is set, and
                // thermalmonitord can take a few seconds to let go after that.
                guard smc.has("Ftst") else { throw Failure("fan \(fan) refused manual mode") }
                try smc.write("Ftst", 1)
                usedFtst = true
                var unlocked = false
                for _ in 0..<20 {
                    if (try? smc.write(modeKey, 1)) != nil, smc.readDouble(modeKey) == 1 {
                        unlocked = true
                        break
                    }
                    usleep(500_000)
                }
                guard unlocked else { throw Failure("fan \(fan) refused manual mode") }
            }
        }
        try smc.write("F\(fan)Tg", rpm)
    }

    private func restore(_ fan: Int) {
        do { try smc.write("F\(fan)Md", 0) } catch { log("restore fan \(fan): \(error)") }
        desired[fan] = nil
        owners[fan] = nil
        // Also clears an Ftst left set by a previous run that crashed.
        if desired.isEmpty && (usedFtst || smc.readDouble("Ftst") == 1) {
            try? smc.write("Ftst", 0)
            usedFtst = false
        }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

let control = FanControl()
log("starting, \(control.count) fans, socket \(socketPath)")
control.restoreAll()

func handle(line: String, client: Int) -> String {
    let parts = line.split(separator: " ").map(String.init)
    switch parts.first {
    case "ping":
        return "ok fanctld \(FanCtlProtocol.version)"
    case "set":
        guard parts.count == 3, let fan = Int(parts[1]), let rpm = Double(parts[2]) else {
            return "err usage: set <fan> <rpm>"
        }
        do {
            return "ok \(Int(try control.setManual(fan: fan, rpm: rpm, client: client)))"
        } catch {
            return "err \(error)"
        }
    case "auto":
        guard parts.count == 2 else { return "err usage: auto <fan|all>" }
        if parts[1] == "all" {
            control.restoreAll()
        } else if let fan = Int(parts[1]), (0..<control.count).contains(fan) {
            control.setAuto(fan: fan)
        } else {
            return "err no fan \(parts[1])"
        }
        return "ok"
    default:
        return "err unknown command"
    }
}

func serve(fd: Int32, client: Int) {
    defer {
        control.clientGone(client)
        close(fd)
    }
    var buffer = [UInt8]()
    var chunk = [UInt8](repeating: 0, count: 512)
    while true {
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 { return }
        buffer.append(contentsOf: chunk[0..<n])
        if buffer.count > 4096 { return }  // nobody sends lines this long
        while let nl = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<nl], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(...nl)
            let reply = Array((handle(line: line, client: client) + "\n").utf8)
            if reply.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) != reply.count { return }
        }
    }
}

// Socket setup
unlink(socketPath)
let listener = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8CString)
guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
    log("socket path too long")
    exit(1)
}
withUnsafeMutableBytes(of: &addr.sun_path) { dst in
    pathBytes.withUnsafeBytes { dst.copyMemory(from: $0) }
}
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard listener >= 0, bound == 0, listen(listener, 4) == 0 else {
    log("cannot listen on \(socketPath): \(String(cString: strerror(errno)))")
    exit(1)
}
// Only root and the installing user may talk to the helper.
chmod(socketPath, 0o600)
if let uid = ownerUID { chown(socketPath, uid, 0) }

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        log("signal \(sig), restoring auto")
        control.restoreAll()
        unlink(socketPath)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let reassertTimer = DispatchSource.makeTimerSource(queue: .global())
reassertTimer.schedule(deadline: .now() + 3, repeating: 3)
reassertTimer.setEventHandler { control.reassert() }
reassertTimer.resume()

Thread {
    var nextClient = 0
    while true {
        let fd = accept(listener, nil, nil)
        if fd < 0 { continue }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == 0 || uid == ownerUID || ownerUID == nil else {
            close(fd)
            continue
        }
        nextClient += 1
        let client = nextClient
        Thread { serve(fd: fd, client: client) }.start()
    }
}.start()

dispatchMain()
