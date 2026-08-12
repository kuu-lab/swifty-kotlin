@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-043: Validates that `Sequence<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R`
/// resolves via the bundled Kotlin source and has no runtime-bridge link.
@Suite
struct SequenceFoldIndexedFunctionTests {
    @Test func testSequenceFoldIndexedResolvesToRuntimeABIWithMatchingResultType() throws {
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
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.foldIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "foldIndexed"
        }, "Expected foldIndexed member call")

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExprID)?.chosenCallee,
            "Expected foldIndexed call to be bound"
        )
        #expect(
            sema.symbols.isSourceBackedSymbol(chosenCallee),
            "Expected Sequence.foldIndexed to resolve to bundled source"
        )

        #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType)
    }

    @Test func testSequenceFoldIndexedWithNamedOperationArgument() throws {
        let ctx = makeContextFromSource("""
        fun weightedSum(values: Sequence<Int>): Int {
            return values.foldIndexed(0, operation = { index, acc, value -> acc + index * value })
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.foldIndexed with named argument to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )
    }
}
