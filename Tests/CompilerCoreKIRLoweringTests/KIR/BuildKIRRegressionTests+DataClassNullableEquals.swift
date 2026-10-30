#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KUU-3108: a nullable `Double?` data class property must compare with
    /// the null-aware canonical `kk_nullable_double_equals` — the property
    /// reaches the comparison as a registered box or the null sentinel, so
    /// `kk_op_eq` would only compare box identity.
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

    // Same contract for `Float?` properties.
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

    // Other nullable primitives compare through the null- and box-aware
    // structural path rather than a raw box-pointer `kk_op_eq`.
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

    // Nullable/non-null properties in one class pick their callees
    // independently.
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
