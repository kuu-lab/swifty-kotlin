#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct FunctionTypedLocalLambdaCallTests {
    private func assertNoSemaErrors(_ source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func lambdaParameterShadowsSameNamedTopLevelFunction() throws {
        try assertNoSemaErrors("""
        fun next(a: String): Int = 1
        fun app(m: (() -> Int) -> Int): Int = 0
        fun main() { app { next -> next() } }
        """)
    }

    @Test
    func implicitItInLambdaPassedToFunctionTypedParameter() throws {
        try assertNoSemaErrors("""
        fun main() { val k: ((Int) -> Int) -> Int = { f -> f(2) }; k { it * 5 } }
        """)
    }

    @Test
    func laterDeclaredAliasInsideFunctionTypeAlias() throws {
        try assertNoSemaErrors("""
        typealias Mw = ((Name) -> Name) -> (Name) -> Name
        typealias Name = String
        fun go(m: Mw): Name = m { it }("q")
        fun main() {
            val m: Mw = { nx -> { x -> nx(x) + "#" } }
            go(m)
        }
        """)
    }
}
#endif
