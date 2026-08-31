@testable import CompilerCore
import Testing

/// KSP-501/KSP-426: List aggregate and extrema functions are bundled Kotlin
/// source definitions rather than residual synthetic runtime declarations.
@Suite
struct ListAggregateHOFSourceMigrationTests {
    private let migratedDefinitions: [(name: String, sourcePath: String)] = [
        ("sumOf", "__bundled_kotlin/collections/ListAggregateHOF.kt"),
        ("maxByOrNull", "__bundled_kotlin/collections/ListExtremaHOF.kt"),
        ("minByOrNull", "__bundled_kotlin/collections/ListExtremaHOF.kt"),
    ]

    @Test
    func residualCollectionsSourceIsEmpty() {
        #expect(BundledStdlib.kotlinCollectionsSource.isEmpty)
    }

    @Test
    func migratedAggregateFunctionsAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)

        for definition in migratedDefinitions {
            let name = definition.name
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == definition.sourcePath
            }

            #expect(!sourceSymbols.isEmpty, "Expected \(name) to be declared in \(definition.sourcePath)")
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil },
                "Expected \(name) bundled source definitions to be List extension functions"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Expected \(name) bundled source definitions to avoid direct C external links"
            )
        }
    }

    @Test
    func migratedAggregateFunctionsHaveNoResidualDuplicate() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)

        for definition in migratedDefinitions {
            let name = definition.name
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let declaringPaths = Set(sema.symbols.lookupAll(fqName: fqName).compactMap { symbolID -> String? in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return nil
                }
                return ctx.sourceManager.path(of: fileID)
            })

            #expect(
                !declaringPaths.contains("__bundled_kotlin_collections_stdlib.kt"),
                "Expected \(name) to no longer be declared by the residual bundled collections source"
            )
        }
    }

    @Test
    func listAggregateCallsTypeCheckCleanly() throws {
        let source = """
        fun sample(values: List<String>) {
            values.sumOf { value -> value.length }
            values.maxByOrNull { value -> value.length }
            values.minByOrNull { value -> value.length }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List aggregate source calls to type-check cleanly, got: \(aggregateDiagnosticSummary(in: ctx))"
        )
    }

    @Test
    func listSumOfSelectsNumericSourceOverloads() throws {
        let source = """
        fun sample(values: List<Int>) {
            values.sumOf { it }
            values.sumOf { it.toLong() }
            values.sumOf { it.toDouble() }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List.sumOf numeric overloads to type-check cleanly, got: \(aggregateDiagnosticSummary(in: ctx))"
        )

        let sumCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "sumOf"
            else {
                return nil
            }
            return exprID
        }
        #expect(sumCalls.count == 3)
        let expectedTypes = [sema.types.intType, sema.types.longType, sema.types.doubleType]
        for (call, expectedType) in zip(sumCalls, expectedTypes) {
            #expect(sema.bindings.exprType(for: call) == expectedType)
            guard let chosenCallee = sema.bindings.callBinding(for: call)?.chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                Issue.record("Expected List.sumOf call to resolve to a source-backed function")
                continue
            }
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(signature.returnType == expectedType)
            guard let parameterType = signature.parameterTypes.first else {
                Issue.record("Expected List.sumOf selector parameter")
                continue
            }
            guard case let .functionType(selectorType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected List.sumOf selector parameter to be a function")
                continue
            }
            #expect(selectorType.returnType == expectedType)
        }
    }
}

private func aggregateDiagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics
        .map { diagnostic in
            guard let range = diagnostic.primaryRange else {
                return "\(diagnostic.code): \(diagnostic.message)"
            }
            let position = ctx.sourceManager.lineColumn(of: range.start)
            return "\(ctx.sourceManager.path(of: range.start.file)):\(position.line):\(position.column): \(diagnostic.code): \(diagnostic.message)"
        }
        .joined(separator: "\n")
}
