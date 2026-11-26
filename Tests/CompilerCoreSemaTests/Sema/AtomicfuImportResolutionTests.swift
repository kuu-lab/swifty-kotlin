#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AtomicfuImportResolutionTests {
    @Test
    func atomicfuImportFormsDoNotCaptureStandardAtomicInt() throws {
        let ctx = makeContextFromSources([
            """
            @file:Suppress("DEPRECATION_ERROR")
            package sample

            import kotlinx.atomicfu.*
            import kotlinx.atomicfu.AtomicInt as AtomicfuInt
            import kotlinx.atomicfu.atomic as atomicfuAtomic
            import kotlin.concurrent.AtomicInt as NativeAtomicInt

            fun viaWildcard(): AtomicInt = atomic(1)
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
