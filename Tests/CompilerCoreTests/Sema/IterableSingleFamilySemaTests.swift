#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IterableSingleFamilySemaTests {
    /// KSP-992: the four generic Iterable.single-family calls must bind to
    /// bundled Kotlin source rather than a runtime bridge or a synthetic stub.
    @Test func testIterableSingleFamilyResolvesToBundledSource() throws {
        let source = """
        fun probe(values: Iterable<String?>) {
            val single: String? = values.single()
            val singlePredicate: String? = values.single { it != null }
            val singleOrNull: String? = values.singleOrNull()
            val singleOrNullPredicate: String? = values.singleOrNull { it == null }
            println(single)
            println(singlePredicate)
            println(singleOrNull)
            println(singleOrNullPredicate)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Iterable.single-family calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedType = sema.types.makeNullable(sema.types.stringType)
            for name in ["single", "singleOrNull"] {
                let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          ctx.interner.resolve(callee) == name,
                          let range = ast.arena.exprRange(exprID),
                          ctx.sourceManager.path(of: range.start.file) == path
                    else { return nil }
                    return exprID
                }

                #expect(calls.count == 2, "Expected two user \(name) calls")
                for call in calls {
                    let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
                    #expect(sema.symbols.isSourceBackedSymbol(chosen))
                    #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                    #expect(
                        ctx.sourceManager.path(of: try #require(sema.symbols.sourceFileID(for: chosen)))
                            == "__bundled_kotlin/collections/Iterables.kt"
                    )
                    #expect(sema.bindings.exprType(for: call) == expectedType)
                }
            }
        }
    }

    @Test func testListSingleOrNullKeepsSpecificSourceOverload() throws {
        let source = """
        fun probe(values: List<Int>): Int? {
            val single = values.singleOrNull()
            val singlePredicate = values.singleOrNull { it > 1 }
            return single ?: singlePredicate
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "singleOrNull",
                      let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path
                else { return nil }
                return exprID
            }

            #expect(calls.count == 2)
            for call in calls {
                let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(chosen))
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                #expect(
                    ctx.sourceManager.path(of: try #require(sema.symbols.sourceFileID(for: chosen)))
                        == "__bundled_kotlin/collections/ListSearchHOF.kt"
                )
                #expect(sema.bindings.exprType(for: call) == sema.types.makeNullable(sema.types.intType))
            }
        }
    }
}
#endif
