import Foundation
import CSMC

public enum SMCError: Error, CustomStringConvertible {
    case call(key: String, code: Int32)
    case unsupportedType(key: String, type: String)

    public var description: String {
        switch self {
        case let .call(key, code):
            // 0xe00002c1 = kIOReturnNotPrivileged: writes need root.
            return "SMC \(key): error 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case let .unsupportedType(key, type):
            return "SMC \(key): cannot encode type '\(type)'"
        }
    }
}

/// Thread-safe access to the AppleSMC. Reads work as any user; writes need root.
public final class SMC {
    public static let shared = SMC()

    public let isOpen: Bool
    private let lock = NSLock()

    private init() {
        isOpen = smc_open() == 0
    }

    public func has(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var info = smc_keyinfo()
        return key.withCString { smc_key_info($0, &info) } == 0
    }

    /// Every key name the SMC exposes (a few thousand on Apple Silicon).
    public func allKeys() -> [String] {
        guard let count = readDouble("#KEY") else { return [] }
        lock.lock(); defer { lock.unlock() }
        var name = [CChar](repeating: 0, count: 5)
        return (0..<UInt32(count)).compactMap { i in
            smc_key_at(i, &name) == 0 ? String(cString: name) : nil
        }
    }

    public func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        lock.lock(); defer { lock.unlock() }
        return readUnlocked(key)
    }

    public func readDouble(_ key: String) -> Double? {
        guard let (type, bytes) = read(key) else { return nil }
        return Self.decode(type: type, bytes: bytes)
    }

    public func write(_ key: String, _ value: Double) throws {
        lock.lock(); defer { lock.unlock() }
        var info = smc_keyinfo()
        let r = key.withCString { smc_key_info($0, &info) }
        guard r == 0 else { throw SMCError.call(key: key, code: r) }
        let type = Self.typeString(info.type)
        guard let bytes = Self.encode(type: type, size: Int(info.size), value: value) else {
            throw SMCError.unsupportedType(key: key, type: type)
        }
        let w = key.withCString { smc_write($0, bytes, UInt32(bytes.count)) }
        guard w == 0 else { throw SMCError.call(key: key, code: w) }
    }

    private func readUnlocked(_ key: String) -> (type: String, bytes: [UInt8])? {
        var info = smc_keyinfo()
        var buf = [UInt8](repeating: 0, count: 32)
        guard key.withCString({ smc_read($0, &info, &buf) }) == 0 else { return nil }
        return (Self.typeString(info.type), Array(buf.prefix(Int(info.size))))
    }

    static func typeString(_ code: UInt32) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xff))) }
        return String(chars)
    }

    static func decode(type: String, bytes b: [UInt8]) -> Double? {
        func be16() -> UInt16 { UInt16(b[0]) << 8 | UInt16(b[1]) }
        switch type {
        case "flt " where b.count == 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "fpe2" where b.count == 2: return Double(be16()) / 4
        case "sp78" where b.count == 2: return Double(Int16(bitPattern: be16())) / 256
        case "ui8 " where b.count == 1: return Double(b[0])
        case "ui16" where b.count == 2: return Double(be16())
        case "ui32" where b.count == 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default: return nil
        }
    }

    static func encode(type: String, size: Int, value: Double) -> [UInt8]? {
        switch (type, size) {
        case ("flt ", 4):
            let bits = Float(value).bitPattern
            return [0, 8, 16, 24].map { UInt8((bits >> $0) & 0xff) }
        case ("fpe2", 2):
            let v = UInt16(max(0, min(value * 4, 65535)))
            return [UInt8(v >> 8), UInt8(v & 0xff)]
        case ("ui8 ", 1):
            return [UInt8(max(0, min(value, 255)))]
        case ("ui16", 2):
            let v = UInt16(max(0, min(value, 65535)))
            return [UInt8(v >> 8), UInt8(v & 0xff)]
        default:
            return nil
        }
    }
}
