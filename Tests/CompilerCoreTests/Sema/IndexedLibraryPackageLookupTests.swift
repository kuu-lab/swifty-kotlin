import Foundation
@testable import CompilerCore
import Testing

@Suite
struct IndexedLibraryPackageLookupTests {
    @Test
    func repeatedChildQueriesPreserveOrderAndLazyDeclarations() throws {
        let records = [
            MetadataRecord(kind: .class, fqName: "demo.zebra.Inner"),
            MetadataRecord(kind: .function, fqName: "demo.alpha.call"),
            MetadataRecord(kind: .class, fqName: "demo.Box"),
            MetadataRecord(kind: .constructor, fqName: "demo.Box.<init>"),
            MetadataRecord(kind: .class, fqName: "demo.zebra.deep.Node"),
            MetadataRecord(kind: .function, fqName: "demo.rejected.call"),
            MetadataRecord(kind: .property, fqName: "demo.alpha.value"),
            MetadataRecord(kind: .function, fqName: "demo.日本語.call"),
        ]
        let file = try #require(IndexedMetadataFile(data: MetadataEncoder().serializeCompactIndexed(records)))
        let interner = StringInterner()
        let symbols = SymbolTable()
        var claimed: [Int] = []
        let provider = DataFlowSemaPhase.IndexedLibrarySource(
            importOrder: 0, indexedFile: file, interner: interner,
            moduleFQN: nil, isStdlibArtifact: false, symbols: symbols,
            rejectedEntryIndices: [5]
        ) { index, _ in
            claimed.append(index)
            return nil
        }
        let demo = ["demo"].map(interner.intern)
        let zebra = ["demo", "zebra"].map(interner.intern)
        let missing = ["demo", "missing"].map(interner.intern)
        func names(_ parent: [InternedString]) -> [String] {
            provider.packagePrefixes(under: parent).map {
                $0.map(interner.resolve).joined(separator: ".")
            }
        }
        for _ in 0..<1000 {
            #expect(names(demo) == ["demo.alpha", "demo.zebra", "demo.日本語"])
            #expect(names(zebra) == ["demo.zebra.deep"])
            #expect(names(missing).isEmpty)
        }
        #expect(claimed.isEmpty, "Package discovery must not materialize declarations")
        provider.drainChildren(parentFQName: ["demo", "alpha"].map(interner.intern), into: symbols)
        #expect(claimed == [1, 6])
        #expect(names(demo) == ["demo.alpha", "demo.zebra", "demo.日本語"])
        #expect(names(missing).isEmpty)
    }

    @Test
    func missingParentInOneProviderDoesNotHideAnotherProviderPackage() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        func provider(_ fqName: String, order: Int) throws -> DataFlowSemaPhase.IndexedLibrarySource {
            let file = try #require(IndexedMetadataFile(data: MetadataEncoder().serializeCompactIndexed([
                MetadataRecord(kind: .class, fqName: fqName),
            ])))
            return DataFlowSemaPhase.IndexedLibrarySource(
                importOrder: order, indexedFile: file, interner: interner,
                moduleFQN: nil, isStdlibArtifact: false, symbols: symbols
            ) { _, _ in nil }
        }
        let first = try provider("other.Root", order: 0)
        let second = try provider("demo.child.Root", order: 1)
        let parent = ["demo"].map(interner.intern)
        #expect(first.packagePrefixes(under: parent).isEmpty)
        #expect(second.packagePrefixes(under: parent) == [["demo", "child"].map(interner.intern)])
        #expect(first.packagePrefixes(under: parent).isEmpty)
    }
}
