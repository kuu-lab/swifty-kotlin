#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    @Test
    func rejectsExplicitReturnOverInferredParentReturn() throws {
        // The header check compares `String` against the parent's `anyType`
        // placeholder and passes silently; the deferred pass must re-check
        // once the inferred `Int` is published.
        let ctx = makeContextFromSource("""
        open class A { open fun f() = 5 }
        class B : A() { override fun f(): String = "s" }
        """)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-OVERRIDE-RETURN"
        }
        #expect(diagnostics.count == 1, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsMatchingExplicitReturnOverInferredParentReturn() throws {
        let ctx = makeContextFromSource("""
        open class A { open fun f() = "x" }
        class B : A() { override fun f(): String = "y" }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
