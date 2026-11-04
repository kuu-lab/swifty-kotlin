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
        // KUU-3961: the assertk Iterable/Sequence shape. `Assert<T>` receivers
        // collapse to the same JVM-erased signature, but the bounds differ, so
        // non-JVM emission must keep them distinct.
        """
        class Assert<T>
        fun <E, T : Iterable<E>> Assert<T>.atLeast(t: Int) {}
        fun <E, T : Sequence<E>> Assert<T>.atLeast(t: Int) {}
        """,
        // A type parameter occurring inside a type argument also carries its
        // bounds into the signature.
        "fun <T : CharSequence> f(value: List<T>) = 1; fun <U : Number> f(value: List<U>) = 2",
    ])
    func distinctNestedUpperBoundsPermitOverloads(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func identicalNestedUpperBoundsStillConflictOnNative() throws {
        try withTemporaryFile(contents: """
        class Assert<T>
        fun <E, T : Iterable<E>> Assert<T>.atLeast(t: Int) {}
        fun <E, T : Iterable<E>> Assert<T>.atLeast(t: Int) {}
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" },
                    "Expected a conflicting declaration: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "fun <T : Number> f(value: T) = 1; fun <U : Number> f(value: U) = 2",
        // Bounds of type parameters that never occur in the signature do not
        // participate: `f(Int)` and `f(Int)` stay a source-level conflict.
        "fun <T : CharSequence> f(value: Int) = 1; fun <U : Number> f(value: Int) = 2",
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
