@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericBoundOverloadConflictTests {
    @Test
    func distinctDirectUpperBoundsPermitOverloads() throws {
        try withTemporaryFile(contents: """
        interface Bounded {
            fun <T : CharSequence> echo(value: T): T
            fun <T : Number> echo(value: T): T
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "fun <T : Number> f(value: T) = 1; fun <U : Number> f(value: U) = 2",
        "fun <T : CharSequence> f(value: Int) = 1; fun <U : Number> f(value: Int) = 2",
        "fun <T : CharSequence> f(value: List<T>) = 1; fun <U : Number> f(value: List<U>) = 2",
        "interface A; interface B; fun <T> f(value: T) where T : A, T : B = 1; fun <U> f(value: U) where U : B, U : A = 2",
        "fun <T> f(value: T) = 1; fun <U : Any?> f(value: U) = 2",
    ])
    func matchingOrErasedBoundsStillConflict(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" },
                    "Expected a conflicting declaration: \(ctx.diagnostics.diagnostics)")
        }
    }
}
