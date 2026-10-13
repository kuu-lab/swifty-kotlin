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

    @Test
    func resultCovarianceComposesInCoroutineMemberSignatures() throws {
        let source = """
        interface Producer<out T> {
            val result: Result<T>
        }
        interface Consumer<in T> {
            fun resumeWith(result: Result<T>)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func producerScopeContravarianceComposesWithChannelGetter() throws {
        let source = """
        import kotlinx.coroutines.channels.ProducerScope
        import kotlinx.coroutines.channels.SendChannel

        interface ProducingTask<in E> {
            val scope: ProducerScope<E>
        }

        fun narrowProducer(scope: ProducerScope<Any>): ProducerScope<String> = scope
        fun channelFrom(scope: ProducerScope<String>): SendChannel<String> = scope.channel
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let producerScope = try #require(sema.symbols.allSymbols().first {
                $0.fqName.map(ctx.interner.resolve).joined(separator: ".") == "kotlinx.coroutines.channels.ProducerScope"
            })
            #expect(sema.types.nominalTypeParameterVariances(for: producerScope.id) == [.in])
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

    @Test(arguments: [
        ("in", "Sink<Source<E>>", 0),
        ("out", "Sink<Sink<E>>", 0),
        ("in", "(E) -> Int", 0),
        ("out", "() -> E", 0),
        ("out", "Cell<out E>", 0),
        ("in", "Cell<in E>", 0),
        ("out", "Source<Int>", 0),
        ("in", "Source<Int>", 0),
        ("in", "Sink<Sink<E>>", 1),
        ("out", "Sink<Source<E>>", 1),
        ("out", "Cell<E>", 1),
        ("in", "Cell<E>", 1),
        ("out", "(E) -> E", 1),
    ])
    func typeAliasVariance(variance: String, underlying: String, expectedViolations: Int) throws {
        let source = """
        interface Source<out E>
        interface Sink<in E>
        interface Cell<E>
        typealias Alias<E> = \(underlying)
        interface Subject<\(variance) T> {
            val value: Alias<T>
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

    // kotlin.UnsafeVariance targets AnnotationTarget.TYPE in Kotlin 2.3.10, so
    // placing it on a value parameter is rejected with an annotation-target
    // error and the variance violation is reported unsuppressed — matching
    // kotlinc, which emits both diagnostics for the same source.
    @Test
    func unsafeVarianceOnValueParameterIsRejected() throws {
        let source = """
        package sample

        class Box<out T> {
            fun accept(@UnsafeVariance value: T): T = value
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let targetErrors = ctx.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
            }
            #expect(targetErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
            let varianceErrors = ctx.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-VARIANCE"
            }
            #expect(varianceErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
