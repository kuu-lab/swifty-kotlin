#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceCallByContextTests {
    @Test(arguments: [EmitMode.kirDump])
    func boundCallByContextualizesEmptyMap(mode: EmitMode) throws {
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
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [EmitMode.kirDump])
    func incompatibleMapKeyTypeStillReportsAnError(mode: EmitMode) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.*
        class Sample { fun value(): Int = 42 }
        fun check() {
            val bound = Sample()::value
            bound.callBy(emptyMap<String, Any?>())
        }
        """, emit: mode)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
    }
}
#endif
