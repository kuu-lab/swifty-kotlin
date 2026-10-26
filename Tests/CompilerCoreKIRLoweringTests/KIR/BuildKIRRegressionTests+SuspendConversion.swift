#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test func testExtensionFunctionValueArgumentGetsSuspendAdapter() throws {
        let source = """
        fun box(): String {
            val foo: String.(suspend () -> Unit) -> String = { this }
            val f: () -> Unit = {}
            return "OK".foo(f)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let adapters = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      ctx.interner.resolve(function.name).hasPrefix("kk_suspend_conversion_")
                else {
                    return nil
                }
                return function
            }
            #expect(adapters.count == 1, "Expected one generated suspend-conversion adapter")
            #expect(adapters.first?.isSuspend == true)
        }
    }
}
#endif
