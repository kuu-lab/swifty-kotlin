@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// kotlinc `USAGE_IS_NOT_INLINEABLE` / `NON_LOCAL_RETURN_NOT_ALLOWED` parity:
/// an `inline` function's functional parameter that is not `noinline` may
/// only be invoked or forwarded to another `inline` callee's inlinable
/// parameter (KUU-3765).
@Suite
struct InlineParameterUsageValidationTests {
    @Test
    func inlineParameterForwardedToNonInlineCalleeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun launchIt(block: () -> Unit) { block() }
        inline fun use(block: () -> Unit) {
            launchIt(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func inlineParameterForwardedToNonInlineMemberCalleeIsRejected() throws {
        let ctx = makeContextFromSource("""
        class Runner {
            fun launchIt(block: () -> Unit) { block() }
        }
        inline fun use(block: () -> Unit) {
            Runner().launchIt(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func inlineParameterInValuePositionIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun use(block: () -> Unit) {
            val f = block
            f()
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func inlineParameterNonInvokeMemberCallIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun use(block: () -> Unit) {
            block.hashCode()
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func inlineParameterForwardedToNoinlineParameterIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun inner(noinline b: () -> Unit) { b() }
        inline fun use(block: () -> Unit) {
            inner(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func crossinlineParameterForwardedToNonInlineCalleeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun launchIt(block: () -> Unit) { block() }
        inline fun use(crossinline block: () -> Unit) {
            launchIt(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    @Test
    func inlineParameterForwardedToCrossinlineParameterIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun inner(crossinline b: () -> Unit) { b() }
        inline fun use(block: () -> Unit) {
            inner(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0450", in: ctx)
    }

    @Test
    func inlineParameterInvokedInsideMaterializedLambdaIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun launchIt(block: () -> Unit) { block() }
        inline fun use(block: () -> Unit) {
            launchIt { block() }
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0450", in: ctx)
    }

    /// KUU-4111: bundled stdlib `map` overloads on ranges, collection indices
    /// and primitive arrays are `inline` like upstream Kotlin, so invoking an
    /// `inline` parameter inside their lambda argument stays in the caller's
    /// inlinable context and must not require `crossinline`.
    @Test
    func inlineParameterInvokedInsideInlinedStdlibMapLambdaIsAccepted() throws {
        let ctx = makeContextFromSource("""
        inline fun <T, R> List<T>.zipWithNextCircular(transform: (a: T, b: T) -> R): List<R> =
            indices.map { i -> transform(get(i), get((i + 1) % size)) }
        fun main() { listOf(1, 2, 3).zipWithNextCircular { a, b -> a + b } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inlineParameterInvokedInsideInlinedRangeAndPrimitiveArrayMapLambdaIsAccepted() throws {
        let ctx = makeContextFromSource("""
        inline fun <R> onRange(transform: (Int) -> R): List<R> =
            (0..2).map { transform(it) }
        inline fun <R> onProgression(transform: (Int) -> R): List<R> =
            (0..4 step 2).map { transform(it) }
        inline fun <R> onIntArray(transform: (Int) -> R, a: IntArray): List<R> =
            a.map { transform(it) }
        fun main() {
            onRange { it }
            onProgression { it }
            onIntArray({ it }, intArrayOf(1))
        }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func directInvocationIsAccepted() throws {
        let ctx = makeContextFromSource("""
        inline fun use(block: () -> Unit) {
            block()
            block.invoke()
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func extensionReceiverParameterInvocationIsAccepted() throws {
        let ctx = makeContextFromSource("""
        class Builder {
            fun run() {}
        }
        inline fun use(builder: Builder, block: Builder.() -> Unit) {
            builder.block()
        }
        fun main() { use(Builder()) { run() } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func forwardToInlinableParameterIsAccepted() throws {
        let ctx = makeContextFromSource("""
        inline fun inner(b: () -> Unit) { b() }
        inline fun use(block: () -> Unit) {
            inner(block)
            inner { block() }
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func noinlineParameterUsageIsAccepted() throws {
        let ctx = makeContextFromSource("""
        fun launchIt(block: () -> Unit) { block() }
        inline fun use(noinline block: () -> Unit) {
            launchIt(block)
            val f = block
            f()
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func crossinlineParameterInsideMaterializedLambdaIsAccepted() throws {
        let ctx = makeContextFromSource("""
        fun launchIt(block: () -> Unit) { block() }
        inline fun use(crossinline block: () -> Unit) {
            launchIt { block() }
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func crossinlineParameterForwardedToCrossinlineParameterIsAccepted() throws {
        let ctx = makeContextFromSource("""
        inline fun inner(crossinline b: () -> Unit) { b() }
        inline fun use(crossinline block: () -> Unit) {
            inner(block)
        }
        fun main() { use { } }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func suspendInlineParameterForwardedToNonInlineCalleeIsRejected() throws {
        let ctx = makeContextFromSource("""
        suspend fun launchIt(block: suspend () -> Unit) { block() }
        inline suspend fun use(block: suspend () -> Unit) {
            launchIt(block)
        }
        fun main() { }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0449", in: ctx)
    }

    private func assertHasDiagnostic(_ code: String, in ctx: CompilationContext) {
        let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
        let descriptions = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
        #expect(found, "Expected diagnostic \(code), got: \(descriptions)")
    }
}
