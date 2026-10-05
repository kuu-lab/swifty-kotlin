@testable import CompilerCore
import Testing

@Suite
struct SequenceAssociationSourceMigrationTests {
    @Test
    func canonicalAliasesBindAllEightSourceOverloads() throws {
        let ctx = makeContextFromSource("""
        import kotlin.sequences.associate as seqAssociate
        import kotlin.sequences.associateBy as seqAssociateBy
        import kotlin.sequences.associateByTo as seqAssociateByTo
        import kotlin.sequences.associateTo as seqAssociateTo
        import kotlin.sequences.associateWith as seqAssociateWith
        import kotlin.sequences.associateWithTo as seqAssociateWithTo

        fun <T> use(values: Sequence<T>, destination: MutableMap<Any?, Any?>) {
            val pairs: Map<T, T> = values.seqAssociate(transform = { it to it })
            val by: Map<T, T> = values.seqAssociateBy(keySelector = { it })
            val transformed: Map<T, T> = values.seqAssociateBy(keySelector = { it }, valueTransform = { it })
            val byTo: MutableMap<Any?, Any?> = values.seqAssociateByTo(destination, keySelector = { it })
            val transformedTo: MutableMap<Any?, Any?> = values.seqAssociateByTo(destination, { it }, { it })
            val to: MutableMap<Any?, Any?> = values.seqAssociateTo(destination, transform = { it to it })
            val with: Map<T, T> = values.seqAssociateWith(valueSelector = { it })
            val withTo: MutableMap<Any?, Any?> = values.seqAssociateWithTo(destination, valueSelector = { it })
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let userFile = try #require(ctx.sourceManager.fileIDs().first { ctx.sourceManager.origin(of: $0) == .user })
        let calls: [ExprID] = ast.arena.exprs.indices.compactMap { index in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(id),
                  range.start.file == userFile,
                  ctx.interner.resolve(name).hasPrefix("seqAssociate")
            else { return nil }
            return id
        }
        #expect(calls.count == 8)
        var chosenSymbols = Set<SymbolID>()
        for call in calls {
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            chosenSymbols.insert(chosen)
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(Array(symbol.fqName.dropLast()).map(ctx.interner.resolve) == ["kotlin", "sequences"])
            #expect(symbol.visibility == .public)
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceAssociations.kt")
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Expected Sequence receiver")
                continue
            }
            #expect(sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", "sequences", "Sequence"])
            if ctx.interner.resolve(symbol.name).hasPrefix("associateWith") {
                let names = signature.valueParameterSymbols.compactMap { sema.symbols.symbol($0)?.name }.map(ctx.interner.resolve)
                #expect(names.last == "valueSelector")
            }
        }
        #expect(chosenSymbols.count == 8)

        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        for name in ["associate", "associateBy", "associateByTo", "associateTo", "associateWith", "associateWithTo"] {
            let oldSequenceOverloads = sema.symbols.lookupAll(fqName: collections + [ctx.interner.intern(name)]).filter {
                guard let receiver = sema.symbols.functionSignature(for: $0)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiver)
                else { return false }
                return sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", "sequences", "Sequence"]
            }
            #expect(oldSequenceOverloads.isEmpty, "No stale kotlin.collections Sequence.\(name) overloads")
        }
    }
}
