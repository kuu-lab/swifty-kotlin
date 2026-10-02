#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `null == false` (and other nullable-primitive vs. non-null literal
/// comparisons) must stay null-aware. kk_op_eq/ne only accept raw
/// Ints, so ABILoweringPass previously normalized a nullable operand to its
/// non-null peer's type via kk_unbox_bool/int/char — which map the runtime
/// null sentinel to 0, collapsing a genuine null into a valid non-null value
/// before the comparison ran. These assert the lowered KIR routes a
/// nullable-primitive `==`/`!=` through kk_structural_eq/ne (which already
/// treats the null sentinel correctly) instead of kk_op_eq/ne, while a
/// non-null primitive comparison keeps using the cheaper kk_op_eq/ne path.
extension LoweringPassRegressionTests {
    private func loweredCallees(for source: String, function functionName: String) throws -> [String] {
        var callees: [String] = []
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .object)
            try runToLowering(ctx)

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Unexpected errors for \(path): \(errors.map(\.message))")
            }

            let module: KIRModule = try #require(ctx.kir)
            let interner = ctx.interner
            let function = try findKIRFunction(named: functionName, in: module, interner: interner)
            callees = extractCallees(from: function.body, interner: interner)
        }
        return callees
    }

    @Test
    func testNullableBooleanEqualsLiteralUsesStructuralEquality() throws {
        let source = """
        fun checkNullableBooleanEqualsFalse(b: Boolean?): Boolean {
            return b == false
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableBooleanEqualsFalse")
        #expect(callees.contains("kk_structural_eq"), "Boolean? == false should use kk_structural_eq, got: \(callees)")
        #expect(!callees.contains("kk_op_eq"), "Boolean? == false must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNullableBooleanNotEqualsLiteralUsesStructuralEquality() throws {
        let source = """
        fun checkNullableBooleanNotEqualsFalse(b: Boolean?): Boolean {
            return b != false
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableBooleanNotEqualsFalse")
        #expect(callees.contains("kk_structural_ne"), "Boolean? != false should use kk_structural_ne, got: \(callees)")
        #expect(!callees.contains("kk_op_ne"), "Boolean? != false must not fall back to raw kk_op_ne, got: \(callees)")
    }

    @Test
    func testNullableIntEqualsLiteralUsesStructuralEquality() throws {
        let source = """
        fun checkNullableIntEqualsZero(i: Int?): Boolean {
            return i == 0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableIntEqualsZero")
        #expect(callees.contains("kk_structural_eq"), "Int? == 0 should use kk_structural_eq, got: \(callees)")
        #expect(!callees.contains("kk_op_eq"), "Int? == 0 must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNonNullBooleanEqualityKeepsRawOpPath() throws {
        let source = """
        fun checkNonNullBooleanEqualsFalse(b: Boolean): Boolean {
            return b == false
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullBooleanEqualsFalse")
        #expect(callees.contains("kk_op_eq"), "Non-null Boolean == false should keep the cheaper kk_op_eq path, got: \(callees)")
        #expect(!callees.contains("kk_structural_eq"), "Non-null Boolean == false should not need structural equality, got: \(callees)")
    }

    @Test
    func testNonNullIntInequalityKeepsRawOpPath() throws {
        let source = """
        fun checkNonNullIntNotEqualsZero(i: Int): Boolean {
            return i != 0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullIntNotEqualsZero")
        #expect(callees.contains("kk_op_ne"), "Non-null Int != 0 should keep the cheaper kk_op_ne path, got: \(callees)")
        #expect(!callees.contains("kk_structural_ne"), "Non-null Int != 0 should not need structural equality, got: \(callees)")
    }

    // Long?/ULong?/Double?/Float? are the only primitives whose full raw
    // (unboxed) value range coincides with the runtime null sentinel
    // (Long.MIN_VALUE, ULong 2^63, -0.0's bit pattern). kk_structural_eq/ne's
    // "raw value equals the sentinel implies null" guess cannot distinguish
    // a genuine null from a genuine value sharing that bit pattern, so these
    // route through kk_nullable_primitive_eq/ne instead, which resolves
    // nullness from each operand's own static-type-known boxing state.

    @Test
    func testNullableLongEqualsLiteralUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkNullableLongEqualsZero(l: Long?): Boolean {
            return l == 0L
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableLongEqualsZero")
        #expect(callees.contains("kk_nullable_primitive_eq"), "Long? == 0L should use kk_nullable_primitive_eq, got: \(callees)")
        #expect(!callees.contains("kk_structural_eq"), "Long? == 0L must not use the sentinel-ambiguous kk_structural_eq, got: \(callees)")
        #expect(!callees.contains("kk_op_eq"), "Long? == 0L must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNullableDoubleNotEqualsLiteralUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkNullableDoubleNotEqualsZero(d: Double?): Boolean {
            return d != 0.0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableDoubleNotEqualsZero")
        #expect(callees.contains("kk_nullable_primitive_ne"), "Double? != 0.0 should use kk_nullable_primitive_ne, got: \(callees)")
        #expect(!callees.contains("kk_op_dne"), "Double? != 0.0 must not fall back to the fixed-IEEE kk_op_dne, got: \(callees)")
    }

    @Test
    func testNullableFloatEqualsLiteralUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkNullableFloatEqualsZero(f: Float?): Boolean {
            return f == 0.0f
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableFloatEqualsZero")
        #expect(callees.contains("kk_nullable_primitive_eq"), "Float? == 0.0f should use kk_nullable_primitive_eq, got: \(callees)")
    }

    @Test
    func testNonNullDoubleInequalityKeepsIEEEPath() throws {
        let source = """
        fun checkNonNullDoubleNotEqualsZero(d: Double): Boolean {
            return d != 0.0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullDoubleNotEqualsZero")
        #expect(callees.contains("kk_op_dne"), "Non-null Double != 0.0 should keep the IEEE-754 kk_op_dne path, got: \(callees)")
        #expect(!callees.contains("kk_nullable_primitive_ne"), "Non-null Double != 0.0 should not need null-aware equality, got: \(callees)")
    }

    @Test
    func testTwoNullableLongsUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkTwoNullableLongs(l: Long?, other: Long?): Boolean {
            return l == other
        }
        """
        let callees = try loweredCallees(for: source, function: "checkTwoNullableLongs")
        #expect(callees.contains("kk_nullable_primitive_eq"), "Long? == Long? should use kk_nullable_primitive_eq, got: \(callees)")
    }

    @Test
    func testNullableLongMixedWithNullableIntStillUsesNullablePrimitiveEquality() throws {
        // A *different* nullable primitive kind on the peer side (Int?,
        // which is not itself sentinel-ambiguous) must still have its own
        // nullability checked at runtime rather than assumed non-null —
        // only the Long? side is what routes this comparison here at all.
        let source = """
        fun checkMixedNullablePrimitives(l: Long?, i: Int?): Boolean {
            return l == i
        }
        """
        let callees = try loweredCallees(for: source, function: "checkMixedNullablePrimitives")
        #expect(callees.contains("kk_nullable_primitive_eq"), "Long? == Int? should use kk_nullable_primitive_eq, got: \(callees)")
    }
}
#endif
