#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1261: GC.MainThreadFinalizerProcessor is a bundled source object.
@Suite
struct GCSourceMigrationTests {
    @Test
    func mainThreadFinalizerProcessorIsSourceBackedObject() throws {
        let ctx = makeContextFromSource(
            """
            @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

            import kotlin.native.runtime.GC

            fun processorType(): GC.MainThreadFinalizerProcessor? = null
            """
        )
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected GC.MainThreadFinalizerProcessor to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let gcFQName = ["kotlin", "native", "runtime", "GC"].map(ctx.interner.intern)
        let processorFQName = gcFQName + [ctx.interner.intern("MainThreadFinalizerProcessor")]
        let gcSymbol = try #require(sema.symbols.lookup(fqName: gcFQName))
        let processorSymbol = try #require(sema.symbols.lookup(fqName: processorFQName))

        #expect(sema.symbols.symbol(gcSymbol)?.kind == .object)
        #expect(sema.symbols.symbol(processorSymbol)?.kind == .object)
        #expect(sema.symbols.isSourceBackedSymbol(processorSymbol))
        #expect(sema.symbols.symbol(processorSymbol)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.parentSymbol(for: processorSymbol) == gcSymbol)

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: processorSymbol))
        #expect(
            ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/native/runtime/GC.kt"
        )
    }

    /// KSP-1263: `GC.MainThreadFinalizerProcessor`'s four members type-check
    /// as instance member reads on the nested `object` singleton.
    ///
    /// Regression coverage for a resolver gap this ticket uncovered: member
    /// lookup on an `object` receiver (`classNameReceiverNominalSymbol` in
    /// `inferRegularMemberCall` only recognizes `class`/`interface`/`enumClass`/
    /// `annotationClass` receivers, by design, so that `Foo.instanceMethod()`
    /// keeps failing when `Foo` has no matching static/companion member) never
    /// fell back to a nested `class`/`enumClass`/`object`/`annotationClass`
    /// declared directly inside that object, so `Outer.Inner` failed to
    /// resolve whenever `Outer` was itself an `object` (as opposed to a
    /// `class`/`interface`/`enumClass`, where the analogous lookup already
    /// existed). See the added fallback at the end of
    /// `inferRegularMemberCallWithoutCandidates` in
    /// `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift`.
    @Test
    func mainThreadFinalizerProcessorPropertiesResolveOnObjectReceiver() throws {
        let ctx = makeContextFromSource(
            """
            @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

            import kotlin.native.runtime.GC

            fun readProperties(): Boolean {
                val available: Boolean = GC.MainThreadFinalizerProcessor.available
                val batchSize: ULong = GC.MainThreadFinalizerProcessor.batchSize
                GC.MainThreadFinalizerProcessor.batchSize = batchSize + 1uL
                val maxTimeInTask = GC.MainThreadFinalizerProcessor.maxTimeInTask
                GC.MainThreadFinalizerProcessor.maxTimeInTask = maxTimeInTask
                val minTimeBetweenTasks = GC.MainThreadFinalizerProcessor.minTimeBetweenTasks
                GC.MainThreadFinalizerProcessor.minTimeBetweenTasks = minTimeBetweenTasks
                return available
            }
            """
        )
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected GC.MainThreadFinalizerProcessor member access to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
