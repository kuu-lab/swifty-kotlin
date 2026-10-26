#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct AnonymousFunctionBlockTrailingExpressionTests {
    @Test
    func anonymousFunctionIsLambdaBlockTrailingExpression() throws {
        try withTemporaryFile(contents: """
        fun <T> block(block: () -> T): T = block()
        fun foo() {}

        fun original(): () -> Unit = block { fun(): Unit { foo() } }
        fun nested(): () -> (() -> Int) = { fun (): Int { return 1 } }
        fun namedLocal(): () -> Int = {
            fun local() = 2
            local()
        }
        fun anonymousReturn(): () -> (() -> Int) = { fun(): Int { return 3 } }
        fun initializer() {
            val value: () -> Int = fun (): Int { return 4 }
        }
        fun nestedLambda(): () -> (() -> Int) = { { 5 } }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
#endif
