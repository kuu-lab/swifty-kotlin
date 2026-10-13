#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AtomicfuImportResolutionTests {
    @Test
    func atomicfuImportFormsDoNotCaptureStandardAtomicInt() throws {
        // This nominal fixture tests import binding only. It intentionally has
        // no atomic operations and is not evidence for atomic semantics.
        let ctx = makeContextFromSources([
            """
            package kotlinx.atomicfu
            class AtomicInt(val marker: Int)
            fun atomic(value: Int): AtomicInt = AtomicInt(value)
            """,
            """
            @file:Suppress("DEPRECATION_ERROR")
            package sample

            import kotlinx.atomicfu.*
            import kotlinx.atomicfu.AtomicInt as AtomicfuInt
            import kotlinx.atomicfu.atomic as atomicfuAtomic
            import kotlin.concurrent.AtomicInt as NativeAtomicInt

            fun viaWildcard(): AtomicInt = AtomicInt(1)
            fun viaAlias(): AtomicfuInt = atomicfuAtomic(2)
            fun viaFullyQualifiedName(): kotlinx.atomicfu.AtomicInt = kotlinx.atomicfu.atomic(3)
            fun standardAtomic(value: NativeAtomicInt): NativeAtomicInt = value
            """,
        ])

        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected wildcard, alias, and fully-qualified atomicfu imports to bind independently of kotlin.concurrent.AtomicInt: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
