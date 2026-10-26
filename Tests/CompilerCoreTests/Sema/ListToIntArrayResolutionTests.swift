#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ListToIntArrayResolutionTests {
    // Exercise both source and imported KLIB paths; the regression affected the latter.
    @Test(arguments: [false, true])
    func listConversionsKeepIntArrayResultType(useArtifact: Bool) throws {
        if useArtifact {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource("""
        fun check(values: List<Int>, collection: Collection<Int>) {
            val fromList: IntArray = values.toIntArray()
            val fromListLiteral: IntArray = listOf(1).toIntArray()
            val content: String = listOf(1, 2, 3).toIntArray().contentToString()
            val roundTrip: List<Int> = listOf(1, 2, 3).toIntArray().toList()
            val fromCollection: IntArray = collection.toIntArray()
            val fromArray: IntArray = arrayOf(1).toIntArray()
        }
        """, emit: useArtifact ? .executable : .kirDump, allowDefaultStdlibLibrary: useArtifact)
        if useArtifact {
            #expect(ctx.options.stdlibLibraryPath != nil)
        }
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected List<Int>.toIntArray() to resolve as IntArray, got: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let intArraySymbol = try #require(sema.symbols.lookup(fqName: KnownCompilerNames(interner: ctx.interner).kotlinIntArrayFQName))
        let intArrayType = sema.types.make(.classType(ClassType(
            classSymbol: intArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let toIntArray = ctx.interner.intern("toIntArray")
        var conversionTypes: [TypeID] = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
                  callee == toIntArray,
                  let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let type = sema.bindings.exprType(for: id)
            else {
                continue
            }
            conversionTypes.append(type)
        }

        #expect(conversionTypes.count == 6)
        #expect(conversionTypes.allSatisfy { $0 == intArrayType }, "Expected all toIntArray calls to return IntArray")
    }
}
#endif
