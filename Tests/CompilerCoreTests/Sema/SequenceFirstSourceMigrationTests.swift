@testable import CompilerCore
import Testing

@Suite
struct SequenceFirstSourceMigrationTests {
    @Test
    func canonicalAliasesBindAllSixSourceOverloads() throws {
        let ctx = makeContextFromSource("""
        import kotlin.sequences.first as seqFirst
        import kotlin.sequences.firstOrNull as seqFirstOrNull
        import kotlin.sequences.firstNotNullOf as seqFirstNotNullOf
        import kotlin.sequences.firstNotNullOfOrNull as seqFirstNotNullOfOrNull
        fun <T> use(values: Sequence<T>) {
            val first: T = values.seqFirst()
            val match: T = values.seqFirst(predicate = { true })
            val nullable: T? = values.seqFirstOrNull()
            val nullableMatch: T? = values.seqFirstOrNull(predicate = { true })
            val transformed: String = values.seqFirstNotNullOf(transform = { if (it == null) null else "hit" })
            val transformedOrNull: String? = values.seqFirstNotNullOfOrNull(transform = { if (it == null) null else "hit" })
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
                  ctx.interner.resolve(name).hasPrefix("seqFirst")
            else { return nil }
            return id
        }
        #expect(calls.count == 6)
        var chosenSymbols = Set<SymbolID>()
        for call in calls {
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            chosenSymbols.insert(chosen)
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(Array(symbol.fqName.dropLast()).map(ctx.interner.resolve) == ["kotlin", "sequences"])
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceConversionsAndSetOps.kt")
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(symbol.flags.contains(.inlineFunction) == !signature.valueParameterSymbols.isEmpty)
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Expected Sequence receiver")
                continue
            }
            #expect(sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", "sequences", "Sequence"])
            let names = signature.valueParameterSymbols.compactMap { sema.symbols.symbol($0)?.name }.map(ctx.interner.resolve)
            if !names.isEmpty {
                #expect(names == [ctx.interner.resolve(symbol.name).hasPrefix("firstNotNull") ? "transform" : "predicate"])
                #expect(signature.valueParameterAllowsNonLocalReturn == [true])
            }
            if ctx.interner.resolve(symbol.name).hasPrefix("firstNotNull") {
                #expect(signature.typeParameterSymbols.count == 2)
                #expect(signature.typeParameterUpperBoundsList[1] == [sema.types.anyType])
                let transform = try #require(signature.parameterTypes.first)
                guard case let .functionType(transformType) = sema.types.kind(of: transform),
                      case let .typeParam(resultType) = sema.types.kind(of: transformType.returnType)
                else {
                    Issue.record("Expected nullable transform result type parameter")
                    continue
                }
                #expect(resultType.symbol == signature.typeParameterSymbols[1])
                #expect(resultType.nullability == .nullable)
            }
        }
        #expect(chosenSymbols.count == 6)

        for name in ["first", "firstOrNull"] {
            let oldSequenceOverloads = sema.symbols.lookupAll(fqName: ["kotlin", "collections", name].map(ctx.interner.intern)).filter {
                guard let receiver = sema.symbols.functionSignature(for: $0)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiver)
                else { return false }
                return sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", "sequences", "Sequence"]
            }
            #expect(oldSequenceOverloads.isEmpty, "No stale kotlin.collections Sequence.\(name) overload")
        }
    }
}
