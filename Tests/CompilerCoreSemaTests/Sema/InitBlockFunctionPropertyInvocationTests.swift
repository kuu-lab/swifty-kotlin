#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct InitBlockFunctionPropertyInvocationTests {
    @Test(arguments: [
        "v = it",
        "value -> v = value",
    ])
    func functionPropertyCallInfersLambdaParameterInInitBlock(_ lambdaBody: String) throws {
        try withTemporaryFile(contents: """
        class P<T>(private val ex: ((T) -> Unit) -> Unit) {
            var v: Any? = null
            init { ex { \(lambdaBody) } }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" })
        }
    }
}
#endif
