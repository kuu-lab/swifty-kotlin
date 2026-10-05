#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharProgressionSourceShellTests {
    @Test func nominalCompanionAndMembersAdoptBundledSource() throws {
        let ctx = makeContextFromSource(
            """
            import kotlin.ranges.CharProgression
            import kotlin.ranges.CharRange
            fun makeProgression(): CharProgression = CharProgression.fromClosedRange('a', 'g', 2)
            fun makeRange(): CharRange = 'a'..'g'
            fun progressionIterator(p: CharProgression): CharIterator = p.iterator()
            fun rangeIterator(r: CharRange): CharIterator = r.iterator()
            """
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Char progression and range must still resolve: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "ranges", "CharProgression"].map(ctx.interner.intern)
        let progression = try #require(sema.symbols.lookup(fqName: fqName))
        let progressionInfo = try #require(sema.symbols.symbol(progression))
        #expect(!progressionInfo.flags.contains(.synthetic))
        #expect(progressionInfo.flags.contains(.openType))
        #expect(sema.symbols.isSourceBackedSymbol(progression))

        let companionFQName = fqName + [ctx.interner.intern("Companion")]
        #expect(sema.symbols.lookupAll(fqName: companionFQName).count == 1)
        let companion = try #require(sema.symbols.companionObjectSymbol(for: progression))
        let companionInfo = try #require(sema.symbols.symbol(companion))
        #expect(companionInfo.kind == .object)
        #expect(companionInfo.visibility == .public)
        #expect(companionInfo.declSite != nil)
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(companion))

        for (member, expectedType) in [("first", sema.types.charType), ("last", sema.types.charType), ("step", sema.types.intType)] {
            let memberFQName = fqName + [ctx.interner.intern(member)]
            let properties = sema.symbols.lookupAll(fqName: memberFQName).filter {
                sema.symbols.symbol($0)?.kind == .property
            }
            #expect(properties.count == 1)
            let property = try #require(properties.first)
            #expect(sema.symbols.symbol(property)?.flags.contains(.synthetic) == false)
            #expect(sema.symbols.isSourceBackedSymbol(property))
            #expect(sema.symbols.parentSymbol(for: property) == progression)
            #expect(sema.symbols.propertyType(for: property) == expectedType)
        }

        for member in ["equals", "hashCode", "toString", "iterator"] {
            let members = sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern(member)]).filter {
                sema.symbols.symbol($0)?.kind == .function
                    && sema.symbols.parentSymbol(for: $0) == progression
            }
            #expect(members.count == 1, "CharProgression.\(member) must have a single member owner")
            let function = try #require(members.first)
            #expect(sema.symbols.symbol(function)?.flags.contains(.synthetic) == false)
            #expect(sema.symbols.isSourceBackedSymbol(function))
            #expect(sema.symbols.externalLinkName(for: function) == nil)
        }
    }

    @Test func explicitCallsBindToProgressionMembers() throws {
        let source = """
        fun inspect(p: CharProgression) {
            p.equals(null)
            p.hashCode()
            p.toString()
            val iterator: CharIterator = p.iterator()
            iterator.nextChar()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.symbols.lookup(fqName: ["kotlin", "ranges", "CharProgression"].map(ctx.interner.intern)))
            let expectedNames = Set(["equals", "hashCode", "toString", "iterator"])
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else { continue }
                let name = ctx.interner.resolve(callee)
                guard expectedNames.contains(name) else { continue }
                let chosen = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                #expect(sema.symbols.parentSymbol(for: chosen) == owner)
                #expect(sema.symbols.isSourceBackedSymbol(chosen))
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                seen.insert(name)
            }
            #expect(seen == expectedNames)
        }
    }
}
#endif
