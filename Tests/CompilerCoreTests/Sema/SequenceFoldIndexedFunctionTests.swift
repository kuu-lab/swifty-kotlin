@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-043: Validates that `Sequence<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R`
/// resolves via the synthetic Sema member stub and links to the
/// `kk_sequence_foldIndexed` runtime entry point.
final class SequenceFoldIndexedFunctionTests: XCTestCase {
    func testSequenceFoldIndexedResolvesToRuntimeABIWithMatchingResultType() throws {
        let ctx = makeContextFromSource("""
        fun weightedSum(values: Sequence<Int>): Int {
            return values.foldIndexed(0) { index, acc, value -> acc + index * value }
        }

        fun taggedConcat(values: Sequence<String>): String {
            return values.foldIndexed("") { index, acc, value -> acc + index.toString() + ":" + value + " " }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.foldIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let callExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "foldIndexed"
        }, "Expected foldIndexed member call")

        let memberFQName = [
            "kotlin", "sequences", "Sequence", "foldIndexed",
        ].map(ctx.interner.intern)
        let foldIndexedMembers = sema.symbols.lookupAll(fqName: memberFQName)
        XCTAssertTrue(
            foldIndexedMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_foldIndexed" },
            "Expected Sequence.foldIndexed synthetic member to link to kk_sequence_foldIndexed"
        )

        XCTAssertEqual(sema.bindings.exprType(for: callExprID), sema.types.intType)
    }

    func testSequenceFoldIndexedWithNamedOperationArgument() throws {
        let ctx = makeContextFromSource("""
        fun weightedSum(values: Sequence<Int>): Int {
            return values.foldIndexed(0, operation = { index, acc, value -> acc + index * value })
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.foldIndexed with named argument to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
