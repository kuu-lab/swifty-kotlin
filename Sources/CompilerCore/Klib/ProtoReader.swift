import Foundation

/// Minimal Protocol Buffers wire-format reader for the Kotlin IR schema
/// (`KotlinIr.proto`, proto2).
///
/// A message is collected into field-number → value lists up front, so
/// decoders look up fields by number without tracking a cursor. Only the
/// wire types used by the Kotlin IR schema are supported: varint, fixed64,
/// length-delimited and fixed32 (groups are rejected).
package struct ProtoFields {
    package enum WireValue: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(ArraySlice<UInt8>)
    }

    private var values: [Int: [WireValue]] = [:]

    /// An empty message — useful as a default for optional sub-messages.
    package static let empty = ProtoFields()

    private init() {}

    package init(_ bytes: ArraySlice<UInt8>) throws {
        var cursor = ProtoCursor(bytes)
        while !cursor.isAtEnd {
            let tag = try cursor.readVarint()
            let field = Int(tag >> 3)
            let wire = tag & 7
            guard field > 0 else {
                throw KlibFormatError.corruptProto("invalid field tag \(tag)")
            }
            switch wire {
            case 0:
                values[field, default: []].append(.varint(try cursor.readVarint()))
            case 1:
                values[field, default: []].append(.fixed64(try cursor.readFixed64()))
            case 2:
                let length = Int(try cursor.readVarint())
                values[field, default: []].append(.bytes(try cursor.readBytes(length)))
            case 5:
                values[field, default: []].append(.fixed32(try cursor.readFixed32()))
            default:
                throw KlibFormatError.corruptProto("unsupported wire type \(wire) on field \(field)")
            }
        }
    }

    package init(_ bytes: [UInt8]) throws {
        try self.init(bytes[...])
    }

    // MARK: - Presence and raw access

    package func has(_ field: Int) -> Bool {
        values[field]?.isEmpty == false
    }

    package func wireValues(_ field: Int) -> [WireValue] {
        values[field] ?? []
    }

    /// Last varint value of `field`, if present.
    package func varint(_ field: Int) -> UInt64? {
        values[field]?.last.flatMap {
            guard case .varint(let v) = $0 else { return nil }
            return v
        }
    }

    package func fixed64(_ field: Int) -> UInt64? {
        values[field]?.last.flatMap {
            guard case .fixed64(let v) = $0 else { return nil }
            return v
        }
    }

    package func fixed32(_ field: Int) -> UInt32? {
        values[field]?.last.flatMap {
            guard case .fixed32(let v) = $0 else { return nil }
            return v
        }
    }

    // MARK: - Scalar accessors (proto2: last value wins)

    /// `int64`/`uint64`; negative `int32`/`int64` values arrive sign-extended.
    package func int64(_ field: Int) -> Int64? {
        varint(field).map { Int64(bitPattern: $0) }
    }

    /// `int32`; truncates the (possibly sign-extended) varint.
    package func int32(_ field: Int) -> Int32? {
        varint(field).map { Int32(truncatingIfNeeded: $0) }
    }

    package func bool(_ field: Int) -> Bool? {
        varint(field).map { $0 != 0 }
    }

    package func string(_ field: Int) -> String? {
        values[field]?.last.flatMap {
            guard case .bytes(let b) = $0 else { return nil }
            return String(decoding: b, as: UTF8.self)
        }
    }

    /// Last length-delimited value, as a nested message.
    package func message(_ field: Int) throws -> ProtoFields? {
        guard let bytes = values[field]?.last.flatMap({ value -> ArraySlice<UInt8>? in
            guard case .bytes(let b) = value else { return nil }
            return b
        }) else { return nil }
        return try ProtoFields(bytes)
    }

    /// All length-delimited values, each decoded as a nested message.
    package func messages(_ field: Int) throws -> [ProtoFields] {
        try wireValues(field).compactMap { value in
            guard case .bytes(let b) = value else { return nil }
            return try ProtoFields(b)
        }
    }

    // MARK: - Repeated scalar accessors (packed or unpacked)

    package func int32List(_ field: Int) throws -> [Int32] {
        try varintList(field).map { Int32(truncatingIfNeeded: $0) }
    }

    package func int64List(_ field: Int) throws -> [Int64] {
        try varintList(field).map { Int64(bitPattern: $0) }
    }

    package func uint64List(_ field: Int) throws -> [UInt64] {
        try varintList(field)
    }

    /// Collects `field` accepting both unpacked varints and packed
    /// length-delimited runs (proto2 allows a mix on the wire).
    private func varintList(_ field: Int) throws -> [UInt64] {
        var result: [UInt64] = []
        for value in wireValues(field) {
            switch value {
            case .varint(let v):
                result.append(v)
            case .bytes(let b):
                var cursor = ProtoCursor(b)
                while !cursor.isAtEnd {
                    result.append(try cursor.readVarint())
                }
            default:
                throw KlibFormatError.corruptProto("field \(field) is not a varint list")
            }
        }
        return result
    }
}

/// Cursor over a byte slice for varint/fixed reads.
package struct ProtoCursor {
    private let bytes: ArraySlice<UInt8>
    private(set) var position: ArraySlice<UInt8>.Index

    package init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.position = bytes.startIndex
    }

    package var isAtEnd: Bool { position >= bytes.endIndex }

    package mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while position < bytes.endIndex {
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else {
                throw KlibFormatError.corruptProto("varint exceeds 64 bits")
            }
        }
        throw KlibFormatError.corruptProto("truncated varint")
    }

    package mutating func readFixed32() throws -> UInt32 {
        guard position + 4 <= bytes.endIndex else {
            throw KlibFormatError.corruptProto("truncated fixed32")
        }
        var value: UInt32 = 0
        for i in 0 ..< 4 {
            value |= UInt32(bytes[position + i]) << (8 * i)
        }
        position += 4
        return value
    }

    package mutating func readFixed64() throws -> UInt64 {
        guard position + 8 <= bytes.endIndex else {
            throw KlibFormatError.corruptProto("truncated fixed64")
        }
        var value: UInt64 = 0
        for i in 0 ..< 8 {
            value |= UInt64(bytes[position + i]) << (8 * i)
        }
        position += 8
        return value
    }

    package mutating func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, position + count <= bytes.endIndex else {
            throw KlibFormatError.corruptProto("truncated length-delimited field")
        }
        let slice = bytes[position ..< position + count]
        position += count
        return slice
    }
}
