#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test
    func dataClassEqualsUsesNullAwareCanonicalDoubleEquality() throws {
        let context = makeContextFromSource("""
        data class D(val x: Double?)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "D", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.contains("kk_nullable_double_equals"))
        #expect(!callees.contains("kk_op_eq"))
    }

    @Test
    func dataClassEqualsUsesNullAwareCanonicalFloatEquality() throws {
        let context = makeContextFromSource("""
        data class F(val x: Float?)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "F", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.contains("kk_nullable_float_equals"))
        #expect(!callees.contains("kk_op_eq"))
    }

    @Test
    func dataClassEqualsUsesStructuralEqualityForOtherNullablePrimitives() throws {
        let context = makeContextFromSource("""
        data class M(val i: Int?, val l: Long?, val b: Boolean?)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "M", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.filter { $0 == "kk_structural_eq" }.count == 3)
        #expect(!callees.contains("kk_op_eq"))
    }

    @Test
    func dataClassEqualsMixesNullAndNonNullFloatingCallees() throws {
        let context = makeContextFromSource("""
        data class X(val a: Double, val b: Double?, val c: Int)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "X", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.filter { $0 == "kk_double_equals" }.count == 1)
        #expect(callees.filter { $0 == "kk_nullable_double_equals" }.count == 1)
        #expect(callees.filter { $0 == "kk_op_eq" }.count == 1)
    }
}
#endif
