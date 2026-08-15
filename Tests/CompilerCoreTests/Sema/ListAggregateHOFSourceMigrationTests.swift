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
