@testable import CompilerCore
import Testing

@Suite
struct VarianceCheckTests {
    @Test
    func continuationGetterComposesDeclarationSiteContravariance() throws {
        let source = """
        import kotlin.coroutines.Continuation
        abstract class Task<in T> {
            abstract val delegate: Continuation<T>
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        ("in", "val value: Sink<T>", 0),
        ("out", "val value: Source<T>", 0),
        ("in", "val value: Source<Sink<T>>", 0),
        ("out", "val value: Sink<Sink<T>>", 0),
        ("out", "fun accept(value: Sink<T>)", 0),
        ("in", "fun accept(value: Source<T>)", 0),
        ("out", "val value: Cell<out T>", 0),
        ("in", "val value: Cell<in T>", 0),
        ("in", "val value: Sink<in T>", 0),
        ("out", "val value: Source<out T>", 0),
        ("out", "val value: Source<*>", 0),
        ("out", "val value: Source<() -> T>", 0),
        ("in", "val value: Source<(T) -> Int>", 0),
        ("out", "val value: Sink<T>", 1),
        ("in", "val value: Source<T>", 1),
        ("in", "val value: Sink<Sink<T>>", 1),
        ("out", "fun accept(value: Source<T>)", 1),
        ("out", "val value: Cell<T>", 1),
        ("in", "val value: Cell<T>", 1),
        ("out", "val value: Cell<Sink<T>>", 1),
        ("in", "val value: Cell<Source<T>>", 1),
        ("out", "val value: Source<Cell<T>>", 1),
        ("out", "val value: Cell<Source<out T>>", 1),
        ("in", "val value: Cell<Sink<in T>>", 1),
        ("out", "val value: Cell<() -> T>", 1),
        ("out", "var value: Source<T>", 1),
        ("in", "var value: Sink<T>", 1),
    ])
    func nestedNominalVariance(variance: String, member: String, expectedViolations: Int) throws {
        let source = """
        interface Source<out E>
        interface Sink<in E>
        interface Cell<E>
        interface Subject<\(variance) T> {
            \(member)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == expectedViolations, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-VARIANCE" })
        }
    }

    @Test
    func nominalResolutionUsesImportsAndEnclosingDeclaration() throws {
        let sources = [
            """
            package producers
            interface Channel<out E>
            """,
            """
            package consumers
            interface Channel<in E>
            """,
            """
            package app
            import consumers.Channel
            import producers.Channel as Producer
            interface Input<in T> {
                val channel: Channel<T>
                fun accept(value: Producer<T>)
            }
            class Outer {
                interface Channel<in E>
                interface Nested<in T> {
                    val channel: Channel<T>
                }
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func unsafeVarianceAnnotationAllowsContravariantUseInCovariantType() throws {
        let source = """
        package sample

        class Box<out T> {
            fun accept(value: @UnsafeVariance T): T = value
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-VARIANCE", in: ctx)
        }
    }
}
