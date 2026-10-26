#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension CallableReferenceCallByContextTests {
    private func check(_ ctx: CompilationContext) throws {
        // Match the production JVM frontend's declaration preparation.
        if ctx.options.emit.isJVM { try JVMPreparationPhase().run(ctx) }
        try runSema(ctx)
    }

    @Test(arguments: [EmitMode.jvmJar])
    func jvmBoundCallByContextualizesEmptyMap(mode: EmitMode) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.*
        class Sample { fun value(): Int = 42 }
        fun check() {
            val bound = Sample()::value
            val inferred: Int = bound.callBy(emptyMap())
            val explicit: Int = bound.callBy(emptyMap<KParameter, Any?>())
            val cast = bound as KFunction<*>
            val erased: Any? = cast.callBy(emptyMap())
        }
        """, emit: mode)
        try check(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [EmitMode.jvmJar])
    func jvmIncompatibleMapKeyTypeStillReportsAnError(mode: EmitMode) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.*
        class Sample { fun value(): Int = 42 }
        fun check() {
            val bound = Sample()::value
            bound.callBy(emptyMap<String, Any?>())
        }
        """, emit: mode)
        try check(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
    }
}
#endif
