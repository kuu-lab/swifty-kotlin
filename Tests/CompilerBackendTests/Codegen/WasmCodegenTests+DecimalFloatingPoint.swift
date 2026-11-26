@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension WasmCodegenTests {
    @Test
    func parsesDecimalFloatingPointExactlyUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func lit(_ s: String) -> KIRExprID { e(.stringLiteral(interner.intern(s))) }
        func int(_ v: Int64) -> KIRExprID { e(.intLiteral(v)) }
        func call(_ name: String, _ args: [KIRExprID]) -> KIRExprID {
            let r = e()
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: r,
                              canThrow: false, thrownResult: nil))
            return r
        }
        func printInt(_ v: KIRExprID) {
            let s = e()
            body.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                              arguments: [v, int(1)], result: s,
                              canThrow: false, thrownResult: nil))
            body.append(println(interner.intern("__kk_println_raw"), s))
        }
        func printDoubleBits(_ s: String) {
            printInt(call("__kk_double_toBits", [call("__kk_string_toDouble", [lit(s)])]))
        }
        func printFloatBits(_ s: String) {
            printInt(call("__kk_float_toBits", [call("__kk_string_toFloat", [lit(s)])]))
        }
        printDoubleBits("0.000000000008333333333333332")
        printDoubleBits("0.000000000008333333333333333")
        printDoubleBits("0.000000000008333333333333334")
        printDoubleBits("8.333333333333332e-12")
        printDoubleBits("2.2250738585072011e-308")
        printDoubleBits("4.9406564584124654e-324")
        printDoubleBits("1.7976931348623159e308")
        printFloatBits("0.1")
        printFloatBits("3.4028235677973366e38")
        printFloatBits("1.4e-45")
        printFloatBits("-0.0")
        printInt(call("__kk_double_toBits", [
            call("kk_bits_to_double", [int(9_218_868_437_227_405_313)]),
        ]))
        printInt(call("__kk_float_toBits", [
            call("kk_bits_to_float", [int(2_143_289_345)]),
        ]))
        printInt(call("kk_op_eq", [
            call("__kk_string_toDoubleOrNull", [lit("not-a-number")]),
            int(Int64.min),
        ]))
        let negativeZeroOrNull = call("__kk_string_toDoubleOrNull", [lit("-0.0")])
        printInt(call("kk_op_ne", [negativeZeroOrNull, int(Int64.min)]))
        printInt(call("kk_op_eq", [
            call("__kk_wasm_unbox_double", [negativeZeroOrNull]),
            int(Int64.min),
        ]))
        let negativeZeroString = call("kk_any_to_string", [negativeZeroOrNull, int(6)])
        body.append(println(interner.intern("__kk_println_raw"), negativeZeroString))
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == """
        4441203716456960977
        4441203716456960978
        4441203716456960978
        4441203716456960977
        4503599627370495
        1
        9218868437227405312
        1036831949
        2139095039
        1
        -2147483648
        9221120237041090560
        2143289344
        1
        1
        1
        -0.0

        """)
    }
}
