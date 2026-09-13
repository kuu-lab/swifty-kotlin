@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-043: Validates that `Sequence<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R`
/// resolves via the bundled Kotlin source and has no runtime-bridge link.
@Suite
struct SequenceFoldIndexedFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testSequenceFoldIndexedResolvesToCanonicalSource
            """
            package sample0

                    fun weightedSum(values: Sequence<Int>): Int {
                        return values.foldIndexed(0) { index, acc, value -> acc + index * value }
                    }

                    fun taggedConcat(values: Sequence<String>): String {
                        return values.foldIndexed("") { index, acc, value -> acc + index.toString() + ":" + value + " " }
                    }

            """,
            // testSequenceFoldIndexedWithNamedOperationArgument
            """
            package sample1

                    fun weightedSum(values: Sequence<Int>): Int {
                        return values.foldIndexed(0, operation = { index, acc, value -> acc + index * value })
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testSequenceFoldIndexedResolvesToCanonicalSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected Sequence.foldIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
                )

                let callExprID = try #require(firstExprID(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "foldIndexed"
                }, "Expected foldIndexed member call")

                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected foldIndexed call to be bound"
                )
                let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                    .map { interner.resolve($0) }
                #expect(fqName == ["kotlin", "sequences", "foldIndexed"])
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosenCallee),
                    "Expected Sequence.foldIndexed to resolve to bundled source"
                )

                #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType)

            }

            // === testSequenceFoldIndexedWithNamedOperationArgument ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected Sequence.foldIndexed with named argument to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
                )

            }

        }
    }

}
