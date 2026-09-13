#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntersectionTypeFlowTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testIntersectionWithAnyMakesTypeParamDefinitelyNonNull
            """
            package sample0

                    fun <T : Any?> identity(x: T & Any): T & Any = x

            """,
            // testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls
            """
            package sample1

                    fun Any.id(): Int = 1

                    fun <T : Any?> direct(x: T & Any): Int = x.id()
                    fun <T : Any?> safe(x: T & Any): Int? = x?.id()

            """,
            // testIntersectionParameterInferenceAtCallSite
            """
            package sample2

                    fun Any.idTag(): Int = 7

                    fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
                    fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

                    fun main() {
                        println(directValue("hello"))
                        println(safeValue("world"))
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testIntersectionWithAnyMakesTypeParamDefinitelyNonNull ===

            do {

                let sample0Path = paths[0]



                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // Exclude bundled stdlib source (e.g. kotlin.random.Random's own `x`
                // field, KSP-466) so this only matches the test's own fixture,
                // regardless of how many other `x`-named declarations the stdlib has.
                let xRef = try #require(firstExprID(in: ast, path: sample0Path, ctx: ctx) { exprID, expr in
                    guard case let .nameRef(name, _) = expr,
                          interner.resolve(name) == "x",
                          let range = ast.arena.exprRange(exprID)
                    else { return false }
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let xType = try #require(sema.bindings.exprType(for: xRef))

                guard case let .intersection(parts) = sema.types.kind(of: xType) else {
                    Issue.record("Expected intersection type for `x`, got \(sema.types.kind(of: xType))")
                    return
                }

                let hasAny = parts.contains { sema.types.kind(of: $0) == .any(.nonNull) }
                let hasTypeParam = parts.contains {
                    if case .typeParam = sema.types.kind(of: $0) {
                        return true
                    }
                    return false
                }

                #expect(hasAny)
                #expect(hasTypeParam)
                #expect(sema.types.isDefinitelyNonNull(xType))
                #expect(sema.types.nullability(of: xType) == .nonNull)
                #expect(!sample0Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample0Diagnostics.map(\.code))")

            }

            // === testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let directCall = try #require(firstExprID(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "id"
                })
                let safeCall = try #require(firstExprID(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .safeMemberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "id"
                })

                #expect(sema.bindings.exprType(for: directCall) == sema.types.intType)
                #expect(
                    sema.bindings.exprType(for: safeCall) == sema.types.makeNullable(sema.types.intType)
                )
                #expect(!sample1Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample1Diagnostics.map(\.code))")

            }

            // === testIntersectionParameterInferenceAtCallSite ===

            do {

                let sample2Path = paths[2]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample2Diagnostics)
                #expect(!sample2Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample2Diagnostics.map(\.code))")

            }

        }
    }

}

#endif
