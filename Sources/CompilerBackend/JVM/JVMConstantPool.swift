import Foundation
import CompilerCore
import RuntimeABI

enum JVMEmissionError: Error, CustomStringConvertible {
    case limit(String)

    var description: String {
        switch self {
        case let .limit(message): message
        }
    }
}

/// Big-endian classfile data. All narrowing conversions are checked by callers.
struct JVMBytes {
    var data = Data()

    mutating func u1(_ value: UInt8) { data.append(value) }
    mutating func u2(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
    mutating func u4(_ value: UInt32) {
        u2(UInt16(truncatingIfNeeded: value >> 16))
        u2(UInt16(truncatingIfNeeded: value))
    }
}

final class JVMConstantPool {
    private var entries: [Data] = []
    // Data keys preserve distinct UTF-16 spellings, unlike Swift String equality.
    private var indices: [Data: UInt16] = [:]

    func intern(_ entry: JVMBytes, wide: Bool = false) throws -> UInt16 {
        if let index = indices[entry.data] { return index }
        guard entries.count + (wide ? 2 : 1) <= 65_534 else {
            throw JVMEmissionError.limit("JVM constant pool exceeds 65534 entries.")
        }
        let index = UInt16(entries.count + 1)
        entries.append(entry.data)
        if wide { entries.append(Data()) }
        indices[entry.data] = index
        return index
    }

    func utf8(_ value: String, kotlinLiteral: Bool = false) throws -> UInt16 {
        let units = kotlinLiteral ? KotlinStringSurrogateEncoding.utf16CodeUnits(value) : Array(value.utf16)
        var encoded = Data()
        // CONSTANT_Utf8 uses modified UTF-8 over UTF-16 code units: NUL is
        // encoded as C0 80 and supplementary characters as two surrogate units.
        for unit in units {
            switch unit {
            case 1...0x7F: encoded.append(UInt8(unit))
            case 0...0x7FF:
                encoded.append(UInt8(0xC0 | (unit >> 6)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            default:
                encoded.append(UInt8(0xE0 | (unit >> 12)))
                encoded.append(UInt8(0x80 | ((unit >> 6) & 0x3F)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            }
        }
        guard encoded.count <= 65_535 else {
            throw JVMEmissionError.limit("A JVM string constant exceeds 65535 modified UTF-8 bytes.")
        }
        var entry = JVMBytes()
        entry.u1(1); entry.u2(UInt16(encoded.count)); entry.data.append(encoded)
        return try intern(entry)
    }

    func single(_ tag: UInt8, _ index: UInt16) throws -> UInt16 {
        var entry = JVMBytes()
        entry.u1(tag); entry.u2(index)
        return try intern(entry)
    }

    func pair(_ tag: UInt8, _ first: UInt16, _ second: UInt16) throws -> UInt16 {
        var entry = JVMBytes()
        entry.u1(tag); entry.u2(first); entry.u2(second)
        return try intern(entry)
    }

    func classInfo(_ name: String) throws -> UInt16 {
        let nameIndex = try utf8(name)
        return try single(7, nameIndex)
    }

    func member(_ tag: UInt8, owner: String, name: String, descriptor: String) throws -> UInt16 {
        let ownerIndex = try classInfo(owner)
        let nameIndex = try utf8(name)
        let descriptorIndex = try utf8(descriptor)
        let nameAndType = try pair(12, nameIndex, descriptorIndex)
        return try pair(tag, ownerIndex, nameAndType)
    }


    func constant(_ constant: JVMConstant) throws -> UInt16 {
        var entry = JVMBytes()
        var wide = false
        switch constant {
        case .null: throw JVMEmissionError.limit("Null is an instruction, not a pool constant.")
        case let .int(n): entry.u1(3); entry.u4(UInt32(bitPattern: n))
        case let .long(n):
            entry.u1(5); let bits = UInt64(bitPattern: n)
            entry.u4(UInt32(truncatingIfNeeded: bits >> 32)); entry.u4(UInt32(truncatingIfNeeded: bits)); wide = true
        case let .float(n): entry.u1(4); entry.u4(n.bitPattern)
        case let .double(n):
            entry.u1(6); let bits = n.bitPattern
            entry.u4(UInt32(truncatingIfNeeded: bits >> 32)); entry.u4(UInt32(truncatingIfNeeded: bits)); wide = true
        case let .string(s): return try single(8, utf8(s, kotlinLiteral: true))
        case let .boolean(b): entry.u1(3); entry.u4(b ? 1 : 0)
        }
        return try intern(entry, wide: wide)
    }

    func write(to bytes: inout JVMBytes) {
        bytes.u2(UInt16(entries.count + 1))
        for entry in entries { bytes.data.append(entry) }
    }
}
