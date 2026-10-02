@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ProtoReaderTests {
    // MARK: - Primitive wire types

    @Test
    func readsVarintsAndFixedValues() throws {
        // field 1 varint 150; field 2 fixed64; field 3 fixed32
        var bytes: [UInt8] = [0x08, 0x96, 0x01]
        bytes.append(0x11) // field 2, wire 1
        bytes += [0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]
        bytes.append(0x1D) // field 3, wire 5
        bytes += [0x78, 0x56, 0x34, 0x12]

        let proto = try ProtoFields(bytes)
        #expect(proto.int32(1) == 150)
        #expect(proto.fixed64(2) == 0x0000_0002_0000_0001)
        #expect(proto.fixed32(3) == 0x1234_5678)
    }

    @Test
    func readsNegativeInt32Varint() throws {
        // field 1 = -1 as a sign-extended 10-byte varint.
        var bytes: [UInt8] = [0x08]
        bytes += [UInt8](repeating: 0xFF, count: 9) + [0x01]
        let proto = try ProtoFields(bytes)
        #expect(proto.int32(1) == -1)
    }

    @Test
    func readsLengthDelimitedStringAndNestedMessage() throws {
        // field 2 = "hi"; field 4 = nested { field 1 varint 7 }
        let bytes: [UInt8] = [
            0x12, 0x02, 0x68, 0x69,
            0x22, 0x02, 0x08, 0x07,
        ]
        let proto = try ProtoFields(bytes)
        #expect(proto.string(2) == "hi")
        let nested = try proto.message(4)
        #expect(nested?.int32(1) == 7)
    }

    @Test
    func packedAndUnpackedVarintListsMerge() throws {
        // field 1 packed [3, 270]; field 1 again unpacked 5 — same field
        // number may appear with both encodings.
        let bytes: [UInt8] = [
            0x0A, 0x03, 0x03, 0x8E, 0x02,
            0x08, 0x05,
        ]
        let proto = try ProtoFields(bytes)
        #expect(try proto.int32List(1) == [3, 270, 5])
    }

    @Test
    func lastValueWinsForNonRepeatedFields() throws {
        let bytes: [UInt8] = [0x08, 0x01, 0x08, 0x02]
        let proto = try ProtoFields(bytes)
        #expect(proto.int32(1) == 2)
    }

    @Test
    func rejectsTruncatedInput() {
        #expect(throws: KlibFormatError.self) {
            _ = try ProtoFields([0x12, 0x05, 0x68]) // length 5, only 1 byte
        }
        #expect(throws: KlibFormatError.self) {
            _ = try ProtoFields([0x08, 0x80]) // unterminated varint
        }
    }

    @Test
    func rejectsUnsupportedWireType() {
        // field 1, wire type 3 (start group — unused by KotlinIr.proto)
        #expect(throws: KlibFormatError.self) {
            _ = try ProtoFields([0x0B])
        }
    }

    @Test
    func rejectsZeroFieldNumber() {
        #expect(throws: KlibFormatError.self) {
            _ = try ProtoFields([0x00, 0x01])
        }
    }
}
