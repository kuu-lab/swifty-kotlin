#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-939: List's size/init factory is a bundled Kotlin declaration; the
/// nominal shell itself is already source-backed via KSP-697 (List.kt).
/// KSP-700: `get`, `isEmpty`, and both `listIterator` overloads are source
/// members with the same `kk_*` link names the synthetic registrations used;
/// other List extension/HOF dispatch remains residual.
@Suite
struct ListInterfaceSourceMigrationTests {
    @Test
    func listInterfaceAndFactoryAreSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            abstract class CustomList : List<String>
            fun widen(values: List<Int>): List<Number> = values
            fun factoryProbe(): List<Int> = List(3) { it }
            fun typeProbe(value: Any): Boolean = value is List<*>
            fun residualProbe(values: List<Int>): Int = values[0]
            """
        )
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected List source declarations to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let collections = ["kotlin", "collections"].map(interner.intern)
        let list = try #require(sema.symbols.lookup(fqName: collections + [interner.intern("List")]))
        let listInfo = try #require(sema.symbols.symbol(list))
        #expect(listInfo.kind == .interface)
        #expect(!listInfo.flags.contains(.synthetic))
        let sourceFile = try #require(sema.symbols.sourceFileID(for: list))
        #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/collections/List/List.kt")
        #expect(sema.types.nominalTypeParameterVariances(for: list) == [.out])

        let collection = try #require(
            sema.symbols.lookup(fqName: collections + [interner.intern("Collection")])
        )
        #expect(sema.symbols.directSupertypes(for: list).contains(collection))

        let factorySymbols = sema.symbols.lookupAll(fqName: collections + [interner.intern("List")]).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListAccessHOF.kt"
                && signature.receiverType == nil
                && signature.parameterTypes.count == 2
                && signature.parameterTypes[0] == sema.types.intType
        }
        #expect(factorySymbols.count == 1)

        let get = try #require(
            sema.symbols.lookup(fqName: collections + [interner.intern("List"), interner.intern("get")])
        )
        // KSP-700: `List.get` is now a source member carrying the same link
        // name the synthetic registration used to install.
        #expect(sema.symbols.symbol(get)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.externalLinkName(for: get) == "__kk_list_get")
        let getFileID = try #require(sema.symbols.sourceFileID(for: get))
        #expect(ctx.sourceManager.path(of: getFileID) == "__bundled_kotlin/collections/List/List.kt")

        let isEmpty = try #require(
            sema.symbols.lookup(fqName: collections + [interner.intern("List"), interner.intern("isEmpty")])
        )
        #expect(sema.symbols.symbol(isEmpty)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.externalLinkName(for: isEmpty) == "kk_list_is_empty")

        let listIteratorMembers = sema.symbols.lookupAll(
            fqName: collections + [interner.intern("List"), interner.intern("listIterator")]
        ).filter { sema.symbols.parentSymbol(for: $0) == list }
        #expect(listIteratorMembers.count == 2)
        #expect(listIteratorMembers.allSatisfy {
            sema.symbols.symbol($0)?.flags.contains(.synthetic) == false
        })
        #expect(
            listIteratorMembers.contains {
                sema.symbols.externalLinkName(for: $0) == "kk_list_iterator"
                    && sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
            }
        )
        #expect(
            listIteratorMembers.contains {
                sema.symbols.externalLinkName(for: $0) == "kk_list_iterator_at"
                    && sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 1
            }
        )
    }
}
#endif
