#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testStringMarginBridgesReserveThrownChannel() throws {
        let source = """
        fun stripMargin(value: String): String {
            return value.trimMargin("")
        }

        fun replaceMargin(value: String): String {
            return value.replaceIndentByMargin("", "")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .llvmIR)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let bridgeCalls = findAllKIRFunctions(in: module).flatMap { function in
                function.body.compactMap { instruction -> (String, Bool, Bool)? in
                    guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction else {
                        return nil
                    }
                    let name = ctx.interner.resolve(callee)
                    guard name == "__kk_string_trimMargin" || name == "__kk_string_replaceIndentByMargin" else {
                        return nil
                    }
                    return (name, canThrow, thrownResult != nil)
                }
            }

            #expect(Set(bridgeCalls.map(\.0)) == [
                "__kk_string_trimMargin",
                "__kk_string_replaceIndentByMargin",
            ])
            #expect(bridgeCalls.allSatisfy { $0.1 && $0.2 })
        }
    }
}
#endif
