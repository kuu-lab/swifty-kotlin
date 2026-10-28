#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KUU-3180: `"1234$a"` where `a` is a member `const val` is a
    /// compile-time constant on the JVM — folded into one interned literal,
    /// so identical non-const initializers in different objects share one
    /// string instance (`A.bNonConst === B.bNonConst` in kt9532). The object
    /// initializer must emit the folded literal instead of a runtime
    /// `__kk_string_concat_flat`, which would allocate a fresh string per
    /// object and break referential equality.
    @Test func testBuildKIRFoldsConstStringTemplateInObjectInitializer() throws {
        let ctx = makeContextFromSource("""
        object A {
            const val a: String = "$"
            val bNonConst = "1234$a"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let initFunction = try #require(
            findAllKIRFunctions(in: module).first {
                ctx.interner.resolve($0.name).hasPrefix("__object_lazy_init_")
            },
            "Expected an __object_lazy_init_ function"
        )
        let callees = extractCallees(from: initFunction.body, interner: ctx.interner)
        #expect(!callees.contains(runtimeCallee(.stringConcatFlat)))
        #expect(initFunction.body.contains { instruction in
            guard case let .constValue(_, value) = instruction,
                  case let .stringLiteral(text) = value
            else { return false }
            return ctx.interner.resolve(text) == "1234$"
        })
    }

    /// The same template must remain a runtime concatenation when the
    /// interpolated property is NOT `const`: a plain `val` is not a
    /// compile-time constant on the JVM, and folding it would wrongly intern
    /// a string the JVM allocates per evaluation (`A.s !== B.s` there).
    @Test func testBuildKIRKeepsNonConstStringTemplateAsRuntimeConcat() throws {
        let ctx = makeContextFromSource("""
        val a: String = "$"
        object A {
            val bNonConst = "1234$a"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let initFunction = try #require(
            findAllKIRFunctions(in: module).first {
                ctx.interner.resolve($0.name).hasPrefix("__object_lazy_init_")
            },
            "Expected an __object_lazy_init_ function"
        )
        let callees = extractCallees(from: initFunction.body, interner: ctx.interner)
        #expect(callees.contains(runtimeCallee(.stringConcatFlat)))
    }
}
#endif
