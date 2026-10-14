@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ArrayWithIndexTests {
    @Test(arguments: [false, true])
    func primitiveIndexedValuesKeepElementTypes(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = ["Byte", "Short", "Int", "Long"].map { type in
            """
            fun check\(type)(xs: \(type)Array) {
                val indexed: Iterable<IndexedValue<\(type)>> = xs.withIndex()
                val iterator: \(type)Iterator = xs.iterator()
                for ((i, x) in indexed) {
                    val index: Int = i
                    val value: \(type) = x
                }
            }
            """
        }.joined(separator: "\n") + "\nfun main() {}"
        let ctx = makeContextFromSource(
            source, emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["withIndex", "iterator"] {
            let calls = memberCallExprIDs(named: name, in: ast, interner: ctx.interner)
                .filter { isUserSourceExpr($0, in: ctx) }
            #expect(calls.count == 4)
            for call in calls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName ==
                    ["kotlin", "collections", name].map(ctx.interner.intern))
            }
        }
    }
}
