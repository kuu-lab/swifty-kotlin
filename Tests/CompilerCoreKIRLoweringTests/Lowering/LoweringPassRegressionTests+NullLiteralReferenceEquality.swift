#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3865: `x == null` / `x != null` lowers to `x === null` /
/// `x !== null` on the JVM — a raw slot check that never calls
/// `Any.equals`. Sending a reference operand through kk_structural_eq
/// asks the registered erased-Any equals override about the null
/// sentinel instead, which flips the result for overrides that answer
/// true for null (e.g. an `equals`-SAM wrapper `{ it == null }`).
/// These tests pin the raw kk_op_eq/ne lowering for reference operands
/// while non-literal peers keep the structural path and nullable
/// primitives keep their sentinel-safe path.
extension LoweringPassRegressionTests {
    @Test(arguments: ["x == null", "null == x"])
    func testAnyOperandNullLiteralUsesRawNullCheck(comparison: String) throws {
        let source = """
        fun check(x: Any?): Boolean = \(comparison)
        """
        let callees = try loweredCallees(for: source, function: "check", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.opEq.name), "`\(comparison)` must lower to kk_op_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralEq.name), "`\(comparison)` must not consult Any.equals, got: \(callees)")
    }

    @Test
    func testAnyOperandNotNullLiteralUsesRawNullCheck() throws {
        let source = """
        fun check(x: Any?): Boolean = x != null
        """
        let callees = try loweredCallees(for: source, function: "check", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.opNe.name), "`x != null` must lower to kk_op_ne, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralNe.name), "`x != null` must not consult Any.equals, got: \(callees)")
    }

    @Test
    func testClassOperandNullLiteralUsesRawNullCheck() throws {
        let source = """
        class C
        fun check(c: C?): Boolean = c == null
        """
        let callees = try loweredCallees(for: source, function: "check", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.opEq.name), "class `== null` must lower to kk_op_eq, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.structuralEq.name), "class `== null` must not consult Any.equals, got: \(callees)")
    }

    @Test
    func testReferenceOperandNonLiteralPeerKeepsStructuralEquality() throws {
        let source = """
        fun check(x: Any?, y: Any?): Boolean = x == y
        """
        let callees = try loweredCallees(for: source, function: "check", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.structuralEq.name), "`x == y` must keep Any.equals dispatch, got: \(callees)")
    }

    @Test
    func testNullablePrimitiveNullLiteralKeepsSentinelSafeComparison() throws {
        let source = """
        fun check(x: Long?): Boolean = x == null
        """
        let callees = try loweredCallees(for: source, function: "check", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.nullablePrimitiveEq.name), "`Long? == null` must keep the sentinel-safe path, got: \(callees)")
        #expect(!callees.contains(RuntimeCall.opEq.name), "`Long? == null` must not use raw kk_op_eq, got: \(callees)")
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
}
#endif
