#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InferredOverrideReturnTypeTests {
    @Test
    func rejectsStringReturnForImplicitUnitAbstractMethod() throws {
        let ctx = makeContextFromSource("""
        abstract class A { abstract fun a(); fun b() = "b" }
        class B : A() { override fun a() = "a" }
        """)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-OVERRIDE-RETURN"
        }
        #expect(diagnostics.count == 1, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(
            diagnostics.first?.message == "Override of 'a' has incompatible return type. Expected subtype of 'Unit' but found 'String'.",
            "Got: \(diagnostics.first?.message ?? "<missing diagnostic>")"
        )
    }

    @Test
    func acceptsInferredCovariantAndUnitReturns() throws {
        let ctx = makeContextFromSource("""
        open class A {
            open fun value(): Any = "base"
            open fun action() {}
        }
        class B : A() {
            override fun value() = "child"
            override fun action() = Unit
        }
        """)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-OVERRIDE-RETURN"
        }
        #expect(diagnostics.isEmpty, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
