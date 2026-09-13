#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DataClassComponentNTests {

    // Regression test for the bug reported in PR #1281 follow-up:
    // specializeComponentReturnType was applied only to inferDestructuringDeclExpr
    // but NOT to inferForDestructuringExpr, so for-loop destructuring of generic
    // Pair/tuple types still returned the raw type-parameter instead of the
    // concrete substituted type.

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testForLoopDestructuringPairSpecializesComponentReturnType
            """
            package sample0

                    fun demo() {
                        val pairs: List<Pair<String, Int>> = listOf(Pair("a", 1), Pair("b", 2))
                        for ((k, v) in pairs) {
                            k.length + v
                        }
                    }

            """,
            // testComponentNUsesOwnerVisibilityForPrivateDataClass
            """
            package sample1

                    package test

                    private data class Secret(val value: Int)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testForLoopDestructuringPairSpecializesComponentReturnType ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    "Expected for-loop pair destructuring to compile without sema errors, got: \(sample0Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: ", "))"
                )

            }

            // === testComponentNUsesOwnerVisibilityForPrivateDataClass ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let componentFQName = [
                    interner.intern("test"),
                    interner.intern("Secret"),
                    interner.intern("component1"),
                ]

                let componentSymbolID = try #require(sema.symbols.lookupAll(fqName: componentFQName).first)
                let componentSymbol = try #require(sema.symbols.symbol(componentSymbolID))

                #expect(componentSymbol.visibility == .private)
                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    "Unexpected diagnostics: \(sample1Diagnostics.map(\.message))"
                )

            }

        }
    }

}

#endif
