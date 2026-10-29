#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AtomicfuDelegateInferenceTests {

    /// ktor-utils `Pipeline.interceptors`: `var x: T? by atomic(null)` must
    /// infer the factory type parameter from the declared property type even
    /// though `atomic` has several overloads and `null` is a literal argument.
    @Test
    func mutablePropertyByAtomicNullInfersTypeArgument() throws {
        let ctx = makeContextFromSource("""
            import kotlinx.atomicfu.atomic
            class C {
                private var items: List<String>? by atomic(null)
                fun read(): List<String>? = items
                fun write(v: List<String>?) { items = v }
            }
            """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// A delegate factory whose convention cannot serve the declared property
    /// type must still be rejected.
    @Test
    func atomicDelegateWithIncompatibleValueTypeFails() throws {
        let ctx = makeContextFromSource("""
            import kotlinx.atomicfu.atomic
            class C {
                private var items: Int by atomic("x")
            }
            """)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "atomic(\"x\") cannot back an Int-typed mutable delegate"
        )
    }
}
#endif
