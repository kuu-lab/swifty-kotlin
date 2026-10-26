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
