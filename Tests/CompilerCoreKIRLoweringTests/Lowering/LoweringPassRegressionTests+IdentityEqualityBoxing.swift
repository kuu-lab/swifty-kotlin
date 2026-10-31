#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3861: `===`/`!==` across the boxing boundary must box the primitive
/// operand through the JVM-compatible identity callees (`kk_box_*_static` —
/// cached for Int/Long/Byte/Short/Boolean/Char, fresh for Double/Float and
/// unsigned kinds) and compare handles, matching `if_acmp` on boxed values.
/// Previously the reference operand was unboxed back to raw bits and compared
/// with `kk_op_eq` on words: a boxed `-0.0` in `Any` compared equal to the
/// `-0.0` literal's bit pattern, and a null `Any?` aliased the same word.
/// Two non-null primitive operands keep value equality (JVM folds same-type
/// pairs to `==`; distinct primitive types are rejected in Sema).
extension LoweringPassRegressionTests {
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

    @Test(arguments: ["a === d", "d === a", "a !== d", "d !== a"])
    func testIdentityEqualityAgainstAnyBoxesDoubleOperand(comparison: String) throws {
        let source = """
        fun compare(a: Any, d: Double): Boolean = \(comparison)
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        let equalityCallee = comparison.contains("!") ? RuntimeCall.opNe.name : RuntimeCall.opEq.name
        #expect(callees.contains(RuntimeCall.boxDoubleNonnullStatic.name), "The raw Double operand must be boxed for the identity check: \(callees)")
        #expect(callees.contains(equalityCallee), "Boxed operands compare handles via \(equalityCallee): \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_unbox_") }.isEmpty, "The Any operand must not be unboxed to raw bits: \(callees)")
    }

    @Test(arguments: ["a === i", "i === a"])
    func testIdentityEqualityAgainstAnyBoxesIntOperand(comparison: String) throws {
        let source = """
        fun compare(a: Any, i: Int): Boolean = \(comparison)
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.boxIntStatic.name), "The raw Int operand must be boxed for the identity check: \(callees)")
        #expect(callees.contains(RuntimeCall.opEq.name), "Boxed operands compare handles via kk_op_eq: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_unbox_") }.isEmpty, "The Any operand must not be unboxed to raw bits: \(callees)")
    }

    @Test
    func testIdentityEqualityAgainstNullableAnyBoxesPrimitiveOperand() throws {
        let source = """
        fun compare(a: Any?, d: Double): Boolean = a === d
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        // The nonnull box callee is required here: kk_box_double_static would
        // pass the -0.0 bit pattern (== the null sentinel) through as "null",
        // making `null === -0.0` true.
        #expect(callees.contains(RuntimeCall.boxDoubleNonnullStatic.name), "A non-null Double must box unconditionally: \(callees)")
        #expect(callees.contains(RuntimeCall.opEq.name), "Boxed operands compare handles via kk_op_eq: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_unbox_") }.isEmpty, "The Any? operand must not be unboxed to raw bits: \(callees)")
    }

    @Test
    func testIdentityEqualityBetweenReferencesBoxesNothing() throws {
        let source = """
        fun compare(a: Any, b: Any): Boolean = a === b
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.opEq.name), "Reference identity still compares handles: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_box_") }.isEmpty, "Reference operands keep their handles: \(callees)")
    }

    @Test
    func testIdentityEqualityBetweenNonNullIntsKeepsValueCompare() throws {
        // JVM's deprecated `Int === Int` is `==`: `f(1000, 1000)` is true even
        // though the boxes would differ. Boxing here would flip it to false.
        let source = """
        fun compare(a: Int, b: Int): Boolean = a === b
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.opEq.name), "Int === Int keeps JVM value equality: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_box_") }.isEmpty, "Non-null primitive operands must not box: \(callees)")
    }

    @Test
    func testIdentityEqualityBetweenNonNullDoublesKeepsIEEECompare() throws {
        let source = """
        fun compare(a: Double, b: Double): Boolean = a === b
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains("kk_op_deq"), "Double === Double keeps the IEEE path: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_box_") }.isEmpty, "Non-null primitive operands must not box: \(callees)")
    }

    @Test
    func testIdentityEqualityBetweenNullableAndNonNullIntStillBoxesBoth() throws {
        // KUU-1385 route, kept unchanged: `Int? === Int` boxes both operands so
        // in-cache values converge on the shared JVM-identity box.
        let source = """
        fun compare(a: Int?, b: Int): Boolean = a === b
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.boxIntStatic.name), "Both operands must box for the identity check: \(callees)")
        #expect(callees.contains(RuntimeCall.opEq.name), "Boxed operands compare handles via kk_op_eq: \(callees)")
    }

    @Test
    func testIdentityEqualityAgainstTypeParameterBoxesPrimitiveOperand() throws {
        let source = """
        fun <T> compare(t: T, d: Double): Boolean = t === d
        """
        let callees = try loweredCallees(for: source, function: "compare", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.boxDoubleNonnullStatic.name), "The raw Double operand must be boxed for the identity check: \(callees)")
        #expect(callees.contains(RuntimeCall.opEq.name), "Boxed operands compare handles via kk_op_eq: \(callees)")
        #expect(callees.filter { $0.hasPrefix("kk_unbox_") }.isEmpty, "The type-parameter operand must not be unboxed to raw bits: \(callees)")
    }
}
#endif
