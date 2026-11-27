@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension WasmCodegenTests {
    @Test
    func runsNullablePrimitiveEqualityHelpersUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func int(_ value: Int64) -> KIRExprID { e(.intLiteral(value)) }
        func call(_ name: String, _ arguments: [KIRExprID]) -> KIRExprID {
            let result = e()
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: arguments, result: result,
                              canThrow: false, thrownResult: nil))
            return result
        }
        func printInt(_ value: KIRExprID) {
            let text = call("kk_any_to_string", [value, int(1)])
            body.append(println(interner.intern("__kk_println_raw"), text))
        }
        func compare(_ name: String, _ lhs: KIRExprID, _ rhs: KIRExprID, _ flag: Int64) {
            printInt(call(name, [lhs, rhs, int(flag)]))
        }

        let null = int(Int64.min)
        let five = int(5)
        compare("kk_nullable_primitive_eq", null, null, 1)
        compare("kk_nullable_primitive_ne", null, null, 1)
        compare("kk_nullable_primitive_eq", null, five, 1)
        compare("kk_nullable_primitive_ne", null, five, 1)
        compare("kk_nullable_primitive_eq", five, five, 0)
        compare("kk_nullable_primitive_eq", five, null, 0)

        let negativeZeroDouble = call("kk_box_double_nonnull", [e(.doubleLiteral(-0.0))])
        let positiveZeroDoubleBits = int(0)
        let doubleNaNBits = int(Int64(bitPattern: Double.nan.bitPattern))
        let boxedDoubleNaN = call("kk_box_double_nonnull", [doubleNaNBits])
        compare("kk_nullable_primitive_eq", negativeZeroDouble, positiveZeroDoubleBits, 2)
        compare("kk_nullable_primitive_ne", negativeZeroDouble, positiveZeroDoubleBits, 2)
        compare("kk_nullable_primitive_eq", boxedDoubleNaN, doubleNaNBits, 2)
        compare("kk_nullable_primitive_ne", boxedDoubleNaN, doubleNaNBits, 2)
        compare("kk_nullable_primitive_eq", null, positiveZeroDoubleBits, 2)
        let positiveZeroDouble = call("kk_box_double_nonnull", [positiveZeroDoubleBits])
        compare("kk_nullable_primitive_eq", negativeZeroDouble, positiveZeroDouble, 4)
        compare("kk_nullable_primitive_eq", boxedDoubleNaN, boxedDoubleNaN, 4)
        compare("kk_nullable_primitive_eq", null, null, 4)

        let negativeZeroFloat = call("kk_box_float", [int(Int64(Int32.min))])
        let positiveZeroFloatBits = int(0)
        let floatNaNBits = int(Int64(Float.nan.bitPattern))
        let boxedFloatNaN = call("kk_box_float", [floatNaNBits])
        compare("kk_nullable_primitive_eq", negativeZeroFloat, positiveZeroFloatBits, 3)
        compare("kk_nullable_primitive_eq", boxedFloatNaN, floatNaNBits, 3)
        let positiveZeroFloat = call("kk_box_float", [positiveZeroFloatBits])
        compare("kk_nullable_primitive_eq", negativeZeroFloat, positiveZeroFloat, 5)
        compare("kk_nullable_primitive_eq", boxedFloatNaN, boxedFloatNaN, 5)
        compare("kk_nullable_primitive_eq", null, null, 5)
        compare("kk_nullable_primitive_eq", null, positiveZeroFloat, 5)

        let boxedLongMinimum = call("kk_box_long_nonnull", [int(Int64.min)])
        compare("kk_nullable_primitive_eq", boxedLongMinimum, null, 1)
        compare("kk_nullable_primitive_ne", boxedLongMinimum, null, 1)
        compare("kk_nullable_primitive_eq", boxedLongMinimum, int(Int64.min), 0)
        let unboxedLongMinimum = call("kk_unbox_long", [boxedLongMinimum])
        compare("kk_nullable_primitive_eq", call("kk_op_add", [unboxedLongMinimum, int(1)]), int(Int64.min + 1), 0)
        let boxedULongHighBit = call("kk_box_ulong_nonnull", [int(Int64.min)])
        compare("kk_nullable_primitive_eq", boxedULongHighBit, null, 1)
        compare("kk_nullable_primitive_eq", boxedULongHighBit, int(Int64.min), 0)
        let unboxedULongHighBit = call("kk_unbox_ulong", [boxedULongHighBit])
        compare("kk_nullable_primitive_eq", call("kk_op_add", [unboxedULongHighBit, int(1)]), int(Int64.min + 1), 0)

        let counterClassID = int(7_001)
        let otherClassID = int(7_002)
        let counterOne = call("kk_tag_value_class_box", [int(1), counterClassID])
        let counterOneCopy = call("kk_tag_value_class_box", [int(1), counterClassID])
        let counterTwo = call("kk_tag_value_class_box", [int(2), counterClassID])
        let otherCounterOne = call("kk_tag_value_class_box", [int(1), otherClassID])
        compare("kk_nullable_primitive_eq", counterOne, counterOneCopy, 0)
        compare("kk_nullable_primitive_eq", counterOne, counterTwo, 0)
        compare("kk_nullable_primitive_eq", counterOne, otherCounterOne, 0)
        let boxedNullCounter = call("kk_value_class_box", [null, counterClassID])
        let boxedNullCounterCopy = call("kk_value_class_box", [null, counterClassID])
        compare("kk_nullable_primitive_eq", boxedNullCounter, null, 1)
        compare("kk_nullable_primitive_eq", boxedNullCounter, boxedNullCounterCopy, 0)
        let retaggedCounter = call("kk_tag_value_class_box", [counterOne, counterClassID])
        compare("kk_nullable_primitive_eq", counterOne, retaggedCounter, 0)
        let unboxedCounter = call("kk_value_class_unbox", [counterOne, counterClassID])
        compare("kk_nullable_primitive_eq", unboxedCounter, int(1), 0)

        let boxedNegativeZeroDouble = call("kk_box_double_nonnull", [int(Int64(bitPattern: Double(-0.0).bitPattern))])
        let boxedPositiveZeroDouble = call("kk_box_double_nonnull", [int(0)])
        compare("kk_nullable_primitive_eq", boxedNegativeZeroDouble, boxedPositiveZeroDouble, 0)
        compare("kk_nullable_primitive_ne", boxedNegativeZeroDouble, boxedPositiveZeroDouble, 0)
        let boxedDoubleNaNOne = call("kk_box_double_nonnull", [doubleNaNBits])
        let boxedDoubleNaNTwo = call("kk_box_double_nonnull", [int(Int64(bitPattern: 0x7ff8_0000_0000_0001))])
        compare("kk_nullable_primitive_eq", boxedDoubleNaNOne, boxedDoubleNaNTwo, 0)

        let boxedNegativeZeroFloat = call("kk_box_float", [int(Int64(Float(-0.0).bitPattern))])
        let boxedPositiveZeroFloat = call("kk_box_float", [int(0)])
        compare("kk_nullable_primitive_eq", boxedNegativeZeroFloat, boxedPositiveZeroFloat, 0)
        let boxedFloatNaNOne = call("kk_box_float", [floatNaNBits])
        let boxedFloatNaNTwo = call("kk_box_float", [int(Int64(0x7fc0_0001))])
        compare("kk_nullable_primitive_eq", boxedFloatNaNOne, boxedFloatNaNTwo, 0)

        let addressPayload = int(4096)
        let taggedAddressPayload = call("kk_tag_value_class_box_with_payload", [
            call("kk_box_long_nonnull", [addressPayload]), addressPayload, counterClassID,
        ])
        let taggedAddressPayloadCopy = call("kk_tag_value_class_box_with_payload", [
            call("kk_box_long_nonnull", [int(4096)]), int(4096), counterClassID,
        ])
        let taggedMinimumPayload = call("kk_tag_value_class_box_with_payload", [
            call("kk_box_long_nonnull", [null]), null, counterClassID,
        ])
        compare("kk_nullable_primitive_eq", taggedAddressPayload, taggedAddressPayloadCopy, 0)
        compare("kk_nullable_primitive_eq", taggedAddressPayload, taggedMinimumPayload, 0)

        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0, "Node stderr: \(run?.stderr ?? "")")
        #expect(run?.stdout == "1\n0\n0\n1\n1\n0\n1\n0\n0\n1\n0\n1\n0\n1\n1\n0\n1\n0\n1\n0\n0\n1\n1\n1\n0\n1\n1\n1\n0\n0\n0\n1\n1\n1\n0\n1\n1\n0\n1\n1\n0\n")
    }
}
