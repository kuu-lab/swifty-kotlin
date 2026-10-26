#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct OverloadedGenericCallExpectedTypeTests {
    @Test
    func returnedLambdaImplicitItUsesOverloadedCallExpectedResult() throws {
        try withTemporaryFile(contents: """
        fun <R> generic(block: () -> R): R = block()
        fun <T, R> T.generic(block: T.() -> R): R = block()
        fun <R> single(block: () -> R): R = block()
        val runFoo: ((String) -> String) = run { { it } }
        val foo: ((String) -> String) = generic { { it } }
        val noOverload: ((String) -> String) = single { { it } }
        val explicitInner: ((String) -> String) = generic { { value: String -> value } }
        val explicitResult: ((String) -> String) = generic<(String) -> String> { { it } }
        fun runBox(): String = runFoo("OK")
        fun box(): String = foo("OK")
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected the inner lambda's implicit `it` to infer as String, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func genuinelyAmbiguousOverloadRemainsRejected() throws {
        try withTemporaryFile(contents: """
        fun <R> ambiguous(block: () -> R, marker: String): R = block()
        fun <R> ambiguous(block: () -> R, marker: Int): R = block()
        val result: String = ambiguous({ "OK" }, TODO())
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" },
                "Expected incompatible overloads to remain ambiguous, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
