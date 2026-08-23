@testable import CompilerCore
import Testing

/// KSP-944: MutableList's nominal shell and size/init factory are bundled
/// Kotlin declarations; mutation members remain compiler/runtime residuals.
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
    }
}
