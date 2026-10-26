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
    @Test
    func testSetOfMixedLongLiteralBoxesBothElementsAsLong() throws {
        let source = """
        fun main() {
            val values = setOf(1, 1L)
            println(values.size)
        }
        """
        let callees = try loweredCallees(for: source, function: "main")
        let boxCallees = callees.filter { $0.hasPrefix("kk_box_") }
        let longBoxes = boxCallees.filter { $0.hasPrefix("kk_box_long") }
        #expect(longBoxes.count == 2, "Both set elements must be boxed as Long: \(boxCallees)")
        #expect(!boxCallees.contains(RuntimeCall.boxIntStatic.name), "No set element should be boxed as Int: \(boxCallees)")
    }

    @Test
    func testGenericCallsBoxContextualLongIntegerLiteralsAsLong() throws {
        let source = """
        fun <T> eq(a: T, b: T): Boolean = a == b
        fun longResult(): Long = 0L

        fun main() {
            eq(0, 0L)
            eq(0, longResult())
            val value: Long = 0
            eq(0, value)
        }
        """
        let callees = try loweredCallees(for: source, function: "main", includeStdlib: false)
        #expect(callees.filter { $0 == RuntimeCall.boxLongNonnullStatic.name }.count == 6, "Every Long argument to eq must be boxed as Long: \(callees)")
        #expect(!callees.contains(RuntimeCall.boxIntStatic.name), "A Long-context integer literal must not be boxed as Int: \(callees)")
    }

    @Test(arguments: ["raw", "amount", "amount()"])
    func testNullableValueClassSafeAccessBoxesNonNullLongResult(member: String) throws {
        let source = """
        value class Counter(val raw: Long) {
            val amount: Long get() = raw
            fun amount(): Long = raw
        }
        fun sentinelSafeAccess(c: Counter?): Long? = c?.\(member)
        """
        let callees = try loweredCallees(for: source, function: "sentinelSafeAccess", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.boxLongNonnullStatic.name), "Safe access must box its non-null Long before merging with null: \(callees)")
        #expect(callees.contains(RuntimeCall.unboxLongStatic.name), "Nullable value-class receiver must be unboxed on the non-null branch: \(callees)")
    }

    @Test
    func testNullableValueClassReturnBoxesAndTagsPayload() throws {
        let source = """
        value class Counter(val raw: Long)
        fun sentinelNullableReturn(c: Counter): Counter? = c
        """
        let callees = try loweredCallees(for: source, function: "sentinelNullableReturn", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.boxLongNonnullStatic.name))
        #expect(callees.contains(RuntimeCall.tagValueClassBox.name))
    }

    @Test(arguments: ["c == expected", "expected == c", "c != expected", "expected != c"])
    func testNullableValueClassEqualityUsesSentinelSafeComparison(comparison: String) throws {
        let source = """
        value class Counter(val raw: Long)
        fun sentinelEquality(c: Counter?, expected: Counter): Boolean = \(comparison)
        """
        let callees = try loweredCallees(for: source, function: "sentinelEquality", includeStdlib: false)
        let expected = comparison.contains("!=") ? RuntimeCall.nullablePrimitiveNe.name : RuntimeCall.nullablePrimitiveEq.name
        #expect(callees.contains(expected), "Value-class equality must preserve non-null sentinel payloads: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralEq.name))
        #expect(!callees.contains(RuntimeCall.structuralNe.name))
    }

    private func loweredCallees(for source: String, function functionName: String, includeStdlib: Bool = true) throws -> [String] {
        var callees: [String] = []
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .object, includeStdlib: includeStdlib)
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
        #expect(callees.contains(RuntimeCall.structuralEq.name), "Boolean? == false should use kk_structural_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opEq.name), "Boolean? == false must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNullableBooleanNotEqualsLiteralUsesStructuralEquality() throws {
        let source = """
        fun checkNullableBooleanNotEqualsFalse(b: Boolean?): Boolean {
            return b != false
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableBooleanNotEqualsFalse")
        #expect(callees.contains(RuntimeCall.structuralNe.name), "Boolean? != false should use kk_structural_ne, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opNe.name), "Boolean? != false must not fall back to raw kk_op_ne, got: \(callees)")
    }

    @Test
    func testNullableIntEqualsLiteralUsesStructuralEquality() throws {
        let source = """
        fun checkNullableIntEqualsZero(i: Int?): Boolean {
            return i == 0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableIntEqualsZero")
        #expect(callees.contains(RuntimeCall.structuralEq.name), "Int? == 0 should use kk_structural_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opEq.name), "Int? == 0 must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNonNullBooleanEqualityKeepsRawOpPath() throws {
        let source = """
        fun checkNonNullBooleanEqualsFalse(b: Boolean): Boolean {
            return b == false
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullBooleanEqualsFalse")
        #expect(callees.contains(RuntimeCall.opEq.name), "Non-null Boolean == false should keep the cheaper kk_op_eq path, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralEq.name), "Non-null Boolean == false should not need structural equality, got: \(callees)")
    }

    @Test
    func testNonNullIntInequalityKeepsRawOpPath() throws {
        let source = """
        fun checkNonNullIntNotEqualsZero(i: Int): Boolean {
            return i != 0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullIntNotEqualsZero")
        #expect(callees.contains(RuntimeCall.opNe.name), "Non-null Int != 0 should keep the cheaper kk_op_ne path, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralNe.name), "Non-null Int != 0 should not need structural equality, got: \(callees)")
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
        #expect(callees.contains(RuntimeCall.nullablePrimitiveEq.name), "Long? == 0L should use kk_nullable_primitive_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralEq.name), "Long? == 0L must not use the sentinel-ambiguous kk_structural_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opEq.name), "Long? == 0L must not fall back to raw kk_op_eq, got: \(callees)")
    }

    @Test
    func testNullableDoubleNotEqualsLiteralUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkNullableDoubleNotEqualsZero(d: Double?): Boolean {
            return d != 0.0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableDoubleNotEqualsZero")
        #expect(callees.contains(RuntimeCall.nullablePrimitiveNe.name), "Double? != 0.0 should use kk_nullable_primitive_ne, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opDne.name), "Double? != 0.0 must not fall back to the fixed-IEEE kk_op_dne, got: \(callees)")
    }

    @Test
    func testNullableFloatEqualsLiteralUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkNullableFloatEqualsZero(f: Float?): Boolean {
            return f == 0.0f
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNullableFloatEqualsZero")
        #expect(callees.contains(RuntimeCall.nullablePrimitiveEq.name), "Float? == 0.0f should use kk_nullable_primitive_eq, got: \(callees)")
    }

    @Test
    func testNonNullDoubleInequalityKeepsIEEEPath() throws {
        let source = """
        fun checkNonNullDoubleNotEqualsZero(d: Double): Boolean {
            return d != 0.0
        }
        """
        let callees = try loweredCallees(for: source, function: "checkNonNullDoubleNotEqualsZero")
        #expect(callees.contains(RuntimeCall.opDne.name), "Non-null Double != 0.0 should keep the IEEE-754 kk_op_dne path, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.nullablePrimitiveNe.name), "Non-null Double != 0.0 should not need null-aware equality, got: \(callees)")
    }

    @Test(arguments: ["a == b", "b == a", "a != b", "b != a"])
    func testNonNullDoubleEqualityAgainstAnyBoxesFloatingOperand(comparison: String) throws {
        let source = """
        fun compare(a: Double, b: Any?): Boolean = \(comparison)
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        let equalityCallee = comparison.contains("!=") ? RuntimeCall.structuralNe.name : RuntimeCall.structuralEq.name
        #expect(callees.contains(RuntimeCall.boxDoubleNonnullStatic.name), "A raw Double compared with Any? must keep its runtime type through boxing: \(callees)")
        #expect(callees.contains(equalityCallee), "Double/Any? equality must use structural equality, got: \(callees)")
        #expect(!callees.contains("kk_op_deq"), "Double/Any? equality must not use numeric equality, got: \(callees)")
    }

    @Test
    func testTwoNullableLongsUsesNullablePrimitiveEquality() throws {
        let source = """
        fun checkTwoNullableLongs(l: Long?, other: Long?): Boolean {
            return l == other
        }
        """
        let callees = try loweredCallees(for: source, function: "checkTwoNullableLongs")
        #expect(callees.contains(RuntimeCall.nullablePrimitiveEq.name), "Long? == Long? should use kk_nullable_primitive_eq, got: \(callees)")
    }
}
#endif
