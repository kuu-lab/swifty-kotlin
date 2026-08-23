#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-948: the Set nominal declaration is bundled Kotlin source while the
/// compatibility shell retains only the residual runtime-backed members.
@Suite
struct SetSourceMigrationTests {
    private func makeSema() throws -> CompilationContext {
        let source = """
        fun inspect(values: Set<Int>, collection: Collection<Int>): Boolean {
            val iterator = values.iterator()
            return values.contains(1) && values.containsAll(listOf(1)) &&
                collection.contains(1) && iterator.hasNext()
        }
        """
        var context: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            context = ctx
        }
        return try #require(context)
    }

    @Test
    func setNominalIsSourceBackedWithKotlinVarianceAndCollectionSupertype() throws {
        let ctx = try makeSema()
        let sema = try #require(ctx.sema)
        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        let setSymbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Set")]))
        let collectionSymbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Collection")]))
        let setInfo = try #require(sema.symbols.symbol(setSymbol))
        let collectionInfo = try #require(sema.symbols.symbol(collectionSymbol))
        let sourceFileID = try #require(sema.symbols.sourceFileID(for: setSymbol))

        #expect(!setInfo.flags.contains(.synthetic))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/SetHOF.kt")
        #expect(setInfo.kind == .interface)
        #expect(sema.types.nominalTypeParameterVariances(for: setSymbol) == [.out])
        #expect(sema.symbols.directSupertypes(for: setSymbol) == [collectionSymbol])
        #expect(sema.symbols.supertypeTypeArgs(for: setSymbol, supertype: collectionSymbol).count == 1)

        // KSP-942 remains synthetic on this master; KSP-948 must not import it.
        #expect(collectionInfo.flags.contains(.synthetic))
    }

    @Test
    func setKeepsResidualRuntimeMembersAndBindsSourceContainsAll() throws {
        let ctx = try makeSema()
        let sema = try #require(ctx.sema)
        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        let setFQName = collections + [ctx.interner.intern("Set")]

        for member in ["contains", "isEmpty"] {
            let memberSymbol = try #require(
                sema.symbols.lookup(fqName: setFQName + [ctx.interner.intern(member)])
            )
            #expect(sema.symbols.symbol(memberSymbol)?.flags.contains(.synthetic) == true)
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == (member == "contains" ? "__kk_set_contains" : "__kk_set_is_empty"))
        }

        let ast = try #require(ctx.ast)
        let containsAllCall = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "containsAll"
        })
        let chosenCallee = try #require(sema.bindings.callBinding(for: containsAllCall)?.chosenCallee)
        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
    }
}
#endif
