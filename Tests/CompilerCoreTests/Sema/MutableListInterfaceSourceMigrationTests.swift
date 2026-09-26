@testable import CompilerCore
import Testing

/// KSP-1503: MutableList's nominal shell, mutation surface, and size/init
/// factory are bundled Kotlin declarations; only private bridge helpers retain
/// the runtime ABI links.
@Suite
struct MutableListInterfaceSourceMigrationTests {
    @Test
    func mutableListInterfaceAndFactoryAreSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            abstract class CustomMutableList : MutableList<String>
            fun widen(values: MutableList<Int>): List<Number> = values
            fun asMutableIterable(values: MutableList<Int>): MutableIterable<Int> = values
            fun factoryProbe(): MutableList<Int> = MutableList(3) { it }
            fun typeProbe(value: Any): Boolean = value is MutableList<*>
            fun mutationProbe(values: MutableList<Int>) {
                values[0] = 1
                values.add(1)
                values.add(0, 2)
                values.removeAt(0)
                values.clear()
                values.removeAll(listOf(1))
                values.retainAll(listOf(1))
                values += 1
                values += listOf(2)
                values -= 1
                values -= listOf(2)
            }
            """
        )
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected MutableList source declarations to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let collections = ["kotlin", "collections"].map(interner.intern)
        let mutableList = try #require(sema.symbols.lookup(fqName: collections + [interner.intern("MutableList")]))
        let info = try #require(sema.symbols.symbol(mutableList))
        #expect(info.kind == .interface)
        #expect(!info.flags.contains(.synthetic))
        let sourceFile = try #require(sema.symbols.sourceFileID(for: mutableList))
        #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/collections/MutableList.kt")
        #expect(sema.types.nominalTypeParameterVariances(for: mutableList) == [.invariant])

        let list = try #require(sema.symbols.lookup(fqName: collections + [interner.intern("List")]))
        let mutableCollection = try #require(
            sema.symbols.lookup(fqName: collections + [interner.intern("MutableCollection")])
        )
        #expect(sema.symbols.directSupertypes(for: mutableList).contains(list))
        #expect(sema.symbols.directSupertypes(for: mutableList).contains(mutableCollection))

        let factorySymbols = sema.symbols.lookupAll(fqName: collections + [interner.intern("MutableList")]).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/MutableList.kt"
                && signature.receiverType == nil
                && signature.parameterTypes.count == 2
                && signature.parameterTypes[0] == sema.types.intType
        }
        #expect(factorySymbols.count == 1)

        let sourceMutationMembers: [(String, Int)] = [
            ("set", 1),
            ("add", 2),
            ("removeAt", 1),
            ("clear", 1),
            ("removeAll", 1),
            ("retainAll", 1),
            ("plusAssign", 2),
            ("minusAssign", 2),
        ]
        for (memberName, expectedCount) in sourceMutationMembers {
            let members = sema.symbols.lookupAll(
                fqName: collections + [interner.intern("MutableList"), interner.intern(memberName)]
            )
            #expect(members.count == expectedCount, "Expected MutableList.\(memberName) overloads to be source-backed")
            #expect(members.allSatisfy { symbolID in
                sema.symbols.isSourceBackedSymbol(symbolID)
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            })
        }
    }
}
