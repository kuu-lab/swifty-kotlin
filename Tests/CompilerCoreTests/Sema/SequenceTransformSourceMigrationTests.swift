#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-441: the lazy Sequence transform pipeline is implemented in bundled
/// Kotlin source (`SequenceTransformHOF.kt`) with `Sequence`/`Iterator` object
/// expressions. These tests pin that user calls resolve to those declarations
/// instead of the synthetic `kk_sequence_*` runtime stubs.
@Suite
struct SequenceTransformSourceMigrationTests {
    @Test
    func transformFunctionsAreBundledSourceDefinitions() throws {
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "sequences"].map(ctx.interner.intern)
            let expectedArities: [String: Set<Int>] = [
                "map": [1],
                "mapIndexed": [1],
                "mapNotNull": [1],
                "mapIndexedNotNull": [1],
                "filter": [1],
                "filterNot": [1],
                "filterIndexed": [1],
                "filterNotNull": [0],
                "onEach": [1],
                "onEachIndexed": [1],
                "withIndex": [0],
                "flatMap": [1],
                "flatMapIndexed": [1],
                "flatten": [0],
                "requireNoNulls": [0],
            ]

            for (name, arities) in expectedArities {
                let fqName = packageFQName + [ctx.interner.intern(name)]
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID)
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/sequences/SequenceTransformHOF.kt"
                }
                let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
                })

                #expect(
                    arities.isSubset(of: registeredArities),
                    "Expected \(name) bundled source overloads \(arities), got \(registeredArities)"
                )
                #expect(
                    sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil },
                    "Expected \(name) bundled source definitions to be Sequence extension functions"
                )
                #expect(
                    sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Expected \(name) bundled source definitions to avoid direct C external links"
                )
            }

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected flatMap calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

            let ast = try #require(ctx.ast)
            for calleeName in ["flatMap", "flatMapIndexed"] {
                let callExprIDs = Self.allExprIDs(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == calleeName
                }
                #expect(callExprIDs.count == 2, "Expected two \(calleeName) calls")

                for callExprID in callExprIDs {
                    let binding = try #require(
                        sema.bindings.callBinding(for: callExprID),
                        Comment(rawValue: "Expected a call binding for \(calleeName)")
                    )
                    let chosenCallee = binding.chosenCallee
                    #expect(
                        sema.symbols.symbol(chosenCallee)?.declSite != nil,
                        Comment(rawValue: "Expected \(calleeName) to resolve to the source-backed extension")
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        Comment(rawValue: "Expected \(calleeName) to avoid the kk_sequence_\(calleeName) runtime stub")
                    )
                }
            }
        }
    }

    private static let sharedSources: [String] = [
        """
        fun noop() {}
        """,
        """
        class Node(val next: Node?)

        fun expandSequence(values: Sequence<Int>): Sequence<Int> {
            return values.flatMap { value -> sequenceOf(value, value) }
        }

        fun expandIterable(values: Sequence<Int>): Sequence<Int> {
            return values.flatMap { value -> listOf(value, value) }
        }

        fun expandIndexed(values: Sequence<Int>): Sequence<Int> {
            return values.flatMapIndexed { index, value -> sequenceOf(index, value) }
        }

        fun expandIndexedIterable(values: Sequence<Int>): Sequence<Int> {
            return values.flatMapIndexed { index, value -> listOf(index, value) }
        }
        """,
    ]

    private static func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else { return nil }
            return exprID
        }
    }
}
#endif
