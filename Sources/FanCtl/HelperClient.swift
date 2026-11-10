import Foundation
import SMCKit

/// Persistent connection to fanctld. All socket I/O runs on a private serial queue.
/// Keeping the connection open matters: fanctld returns our fans to Auto when it closes.
final class HelperClient {
    private let queue = DispatchQueue(label: "fanctl.helper")
    private var fd: Int32 = -1

    /// Sends one command; `completion` runs on the main queue with the reply, or nil if unreachable.
    func send(_ command: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let reply = self.roundTrip(command)
            DispatchQueue.main.async { completion(reply) }
        }
    }

    func sendSync(_ command: String) -> String? {
        queue.sync { roundTrip(command) }
    }

    func disconnect() {
        queue.async { self.closeSocket() }
    }

    private func roundTrip(_ command: String) -> String? {
        if fd < 0 && !connect() { return nil }
        let bytes = Array((command + "\n").utf8)
        guard bytes.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == bytes.count else {
            closeSocket()
            return nil
        }
        var reply = [UInt8]()
        var byte: UInt8 = 0
        while true {
            guard read(fd, &byte, 1) == 1 else {
                closeSocket()
                return nil
            }
            if byte == 10 { break }
            reply.append(byte)
        }
        return String(decoding: reply, as: UTF8.self)
    }

    private func connect() -> Bool {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(FanCtlProtocol.socketPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withUnsafeBytes { dst.copyMemory(from: $0) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
        if ok { fd = s } else { close(s) }
        return ok
    }

    private func closeSocket() {
        if fd >= 0 { close(fd) }
        fd = -1
    }
}
