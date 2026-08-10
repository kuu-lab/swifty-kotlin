#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct GroupingSyntheticMemberLinkTests {
    @Test func testGroupingSyntheticMemberLinks() throws {
        let sources = [
            "fun noop() {}",
            """
            fun render(values: List<Int>) {
                val grouping = values.groupingBy { it % 2 }
                val aggregated: Map<Int, Int> = grouping.aggregate { key, accumulator, element, first ->
                    if (first) key + element else accumulator!! + element
                }
                val destination: MutableMap<Int, Int> = mutableMapOf(1 to 100)
                grouping.aggregateTo(destination) { key, accumulator, element, first ->
                    if (first) key + element else accumulator!! + element
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected Grouping synthetic member sources to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // Synthetic Grouping members are registered with the expected external links.
            let expectedExternalLinks = [
                "aggregate": "kk_grouping_aggregate",
                "aggregateTo": "kk_grouping_aggregateTo",
            ]
            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("Grouping"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic Grouping member \(memberName) to be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbolID) == externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }

            // Call sites resolve to the same runtime external links.
            let aggregateCallExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "aggregate"
            })
            let aggregateChosenCallee = try #require(sema.bindings.callBinding(for: aggregateCallExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: aggregateChosenCallee) == "kk_grouping_aggregate",
                "Expected Grouping.aggregate to resolve to kk_grouping_aggregate"
            )

            let aggregateToCallExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "aggregateTo"
            })
            let aggregateToChosenCallee = try #require(sema.bindings.callBinding(for: aggregateToCallExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: aggregateToChosenCallee) == "kk_grouping_aggregateTo",
                "Expected Grouping.aggregateTo to resolve to kk_grouping_aggregateTo"
            )
        }
    }
}
#endif
