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

        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "1\n0\n0\n1\n1\n0\n1\n0\n0\n1\n0\n1\n0\n1\n1\n0\n1\n0\n1\n0\n")
    }
}
