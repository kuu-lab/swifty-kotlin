@testable import CompilerCore
import Testing

@Suite
struct KlibIrDecodingTests {
    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func scalar(_ field: Int, _ value: UInt64) -> [UInt8] {
        varint(UInt64(field << 3)) + varint(value)
    }

    private func message(_ field: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
    }

    @Test
    func rejectsMissingDeclarationOriginAndRequiredNames() throws {
        let base = scalar(1, 0) + scalar(2, 0)
        // anonymous initializer, class, enum entry, property, type parameter.
        for declarator in [1, 2, 4, 7, 8] {
            let valid = message(1, base) + scalar(2, 0)
            _ = try KlibIrDecoding.declaration(ProtoFields(message(declarator, valid)))
            #expect(throws: KlibFormatError.self) {
                _ = try KlibIrDecoding.declaration(ProtoFields(message(declarator, message(1, base))))
            }
        }
        let fieldWithoutOrigin = message(1, scalar(1, 3)) + scalar(2, 0)
        #expect(throws: KlibFormatError.corruptProto("missing required field declaration.origin_name")) {
            _ = try KlibIrDecoding.declaration(ProtoFields(message(5, fieldWithoutOrigin)))
        }
    }

    @Test
    func rejectsMissingRequiredExpressionScalarsAndBlocks() throws {
        let constant = message(5, scalar(6, 42))
        let cases: [(operation: Int, required: [UInt8], remainder: [UInt8])] = [
            (9, scalar(2, 0), scalar(1, 1)),
            (19, scalar(2, 0), scalar(1, 6)),
            (22, scalar(1, 0), []),
            (23, scalar(1, 0), []),
            (14, scalar(2, 0), scalar(1, 2) + message(3, constant)),
            (32, scalar(1, 0), []),
            (33, scalar(1, 0), message(2, constant)),
            (37, scalar(1, 0), []),
            (38, scalar(1, 0), []),
            (11, message(2, []), scalar(1, 5)),
            (43, message(3, []), scalar(4, 0) + scalar(5, 0)),
            (43, scalar(4, 0), message(3, []) + scalar(5, 0)),
            (43, scalar(5, 0), message(3, []) + scalar(4, 0)),
        ]
        for entry in cases {
            _ = try KlibIrDecoding.expression(ProtoFields(message(entry.operation, entry.required + entry.remainder)))
            #expect(throws: KlibFormatError.self) {
                _ = try KlibIrDecoding.expression(ProtoFields(message(entry.operation, entry.remainder)))
            }
        }
    }

    @Test
    func preservesAnnotationCoordinatesAndRequiresConstructorTypeCount() throws {
        let valid = scalar(1, 1) + scalar(2, 0) + scalar(7, 0)
        let annotation = try KlibIrDecoding.annotation(ProtoFields(valid))
        #expect(annotation.localCoordinates == KlibCoordinates(start: 0, end: 0))
        #expect(throws: KlibFormatError.self) {
            _ = try KlibIrDecoding.annotation(ProtoFields(scalar(1, 1)))
        }
    }

    @Test
    func missingExpressionRetainsAbsentTypeAndCoordinates() throws {
        let expression = try KlibIrDecoding.expression(ProtoFields(message(44, [])))
        guard case .missingExpression = expression.kind else {
            Issue.record("expected missing_expression")
            return
        }
        #expect(expression.typeIndex == -1)
        #expect(expression.globalCoordinates == nil)
        #expect(expression.localCoordinates == nil)
    }

    @Test
    func modernOperationTakesPrecedenceOverLegacyFallback() throws {
        let legacy = message(1, message(6, scalar(6, 7)))
        let modern = message(5, scalar(6, 42))
        let expression = try KlibIrDecoding.expression(ProtoFields(legacy + modern))
        guard case .constInt(let value) = expression.kind else {
            Issue.record("expected const int")
            return
        }
        #expect(value == 42)
    }

    @Test
    func rejectsUnknownRequiredEnums() {
        let constant = message(5, scalar(6, 42))
        let typeOp = scalar(1, 255) + scalar(2, 0) + message(3, constant)
        #expect(throws: KlibFormatError.self) {
            _ = try KlibIrDecoding.expression(ProtoFields(message(14, typeOp)))
        }
        #expect(throws: KlibFormatError.self) {
            _ = try KlibIrDecoding.statement(ProtoFields(message(7, scalar(1, 255))))
        }
    }
}
