#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FloatBitsSourceTests {
    @Test
    func testFloatingPointBitConversionsResolveThroughBundledKotlin() throws {
        let source = """
        fun main() {
            val doublePayload = Double.fromBits(0x7FF0000000000123L)
            val floatPayload = Float.fromBits(0x7F800123)
            println(doublePayload.toBits())
            println(doublePayload.toRawBits())
            println(floatPayload.toBits())
            println(floatPayload.toRawBits())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Floating-point bit APIs should type-check")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames: Set<String> = ["fromBits", "toBits", "toRawBits"]
            var resolvedNames: [String] = []

            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      ast.arena.exprRange(exprID)?.start.file == ast.sortedFiles.last?.fileID,
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      expectedNames.contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else {
                    continue
                }

                let name = ctx.interner.resolve(calleeName)
                resolvedNames.append(name)
                if name == "fromBits" {
                    #expect(
                        !sema.symbols.isSourceBackedSymbol(chosenCallee),
                        "fromBits must use the primitive companion fallback"
                    )
                    #expect(
                        ["__kk_double_fromBits", "__kk_float_fromBits"].contains(
                            sema.symbols.externalLinkName(for: chosenCallee)
                        ),
                        "fromBits must resolve to a demoted runtime bridge"
                    )
                } else {
                    #expect(
                        sema.symbols.isSourceBackedSymbol(chosenCallee),
                        "Floating-point member conversion must resolve to bundled Kotlin source"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "The public member conversion wrapper must not carry a runtime link"
                    )
                }
            }

            #expect(resolvedNames.count == 6, "Expected six floating-point bit API calls")
            #expect(resolvedNames.filter { $0 == "fromBits" }.count == 2)
            #expect(resolvedNames.filter { $0 == "toBits" }.count == 2)
            #expect(resolvedNames.filter { $0 == "toRawBits" }.count == 2)
        }
    }
}
#endif
