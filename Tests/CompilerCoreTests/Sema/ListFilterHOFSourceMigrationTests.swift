@testable import CompilerCore
import Testing

@Suite
struct ListFilterHOFSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/collections/ListFilterHOF.kt"

    @Test
    func migratedListFilterFunctionsAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let expectedArities: [String: Set<Int>] = [
            "filter": [1],
            "filterNot": [1],
            "filterNotNull": [0],
            "filterIndexed": [1],
            "filterIsInstance": [0],
            "filterTo": [2],
            "filterNotTo": [2],
            "filterNotNullTo": [1],
            "filterIndexedTo": [2],
            "filterIsInstanceTo": [1],
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
                return ctx.sourceManager.path(of: fileID) == sourcePath
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
                "Expected \(name) bundled source definitions to be List extension functions"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Expected \(name) bundled source definitions to avoid direct C external links"
            )
        }
    }

    @Test
    func migratedListFilterFunctionsDoNotKeepPublicRuntimeLinkedMembers() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let listFQName = ["kotlin", "collections", "List"].map(ctx.interner.intern)
        let oldLink: (String) -> String = { "kk_list_" + $0 }
        let disallowedMemberLinks: [String: Set<String>] = [
            "filter": [oldLink("filter")],
            "filterNot": [oldLink("filterNot")],
            "filterNotNull": [oldLink("filterNotNull")],
            "filterIndexed": [oldLink("filterIndexed")],
            "filterIsInstance": [oldLink("filterIsInstance")],
            "filterTo": [oldLink("filterTo")],
            "filterNotTo": [oldLink("filterNotTo")],
            "filterNotNullTo": [oldLink("filterNotNullTo")],
            "filterIndexedTo": [oldLink("filterIndexedTo")],
            "filterIsInstanceTo": [oldLink("filterIsInstanceTo")],
        ]

        for (name, disallowedLinks) in disallowedMemberLinks {
            let fqName = listFQName + [ctx.interner.intern(name)]
            let memberLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            let leakedLinks = memberLinks.intersection(disallowedLinks)
            #expect(
                leakedLinks.isEmpty,
                "Expected \(name) to be served by bundled source, but found public member links \(leakedLinks)"
            )
        }
    }

    @Test
    func listFilterCallsBindBundledSourceDefinitions() throws {
        let source = """
        fun sampleInts(values: List<Int>, destination: MutableList<Int>) {
            values.filter { value -> value > 0 }
            values.filterNot { value -> value > 0 }
            values.filterIndexed { index, value -> index < value }
            values.filterTo(destination) { value -> value > 0 }
            values.filterNotTo(destination) { value -> value > 0 }
            values.filterIndexedTo(destination) { index, value -> index < value }
        }

        fun sampleNullable(values: List<Int?>, destination: MutableList<Int>) {
            values.filterNotNull()
            values.filterNotNullTo(destination)
        }

        fun sampleAny(values: List<Any>, destination: MutableList<String>) {
            values.filterIsInstance<String>()
            values.filterIsInstanceTo(destination)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List filter source calls to type-check cleanly, got: \(diagnosticSummary(in: ctx))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expectedNames: Set<String> = [
            "filter",
            "filterNot",
            "filterNotNull",
            "filterIndexed",
            "filterIsInstance",
            "filterTo",
            "filterNotTo",
            "filterNotNullTo",
            "filterIndexedTo",
            "filterIsInstanceTo",
        ]
        for name in expectedNames {
            let callExpr = try #require(userMemberCallID(named: name, in: ast, ctx: ctx, excludedPath: sourcePath))
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(symbol.declSite != nil)
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
        }
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
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

private func userMemberCallID(
    named name: String,
    in ast: ASTModule,
    ctx: CompilationContext,
    excludedPath: String
) -> ExprID? {
    firstExprID(in: ast) { exprID, expr in
        guard case let .memberCall(_, callee, _, _, _) = expr,
              ctx.interner.resolve(callee) == name
        else {
            return false
        }
        guard let range = ast.arena.exprRange(exprID) else {
            return true
        }
        return ctx.sourceManager.path(of: range.start.file) != excludedPath
    }
}
