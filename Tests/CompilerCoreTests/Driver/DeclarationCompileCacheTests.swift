#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DeclarationCompileCacheTests {
    private func unit(_ id: String, sig: String = "s", body: String = "b", refs: Set<String> = []) -> DeclarationUnit {
        DeclarationUnit(id: id, signatureHash: sig, bodyHash: body, references: refs)
    }

    private func graph(_ units: DeclarationUnit...) -> DeclarationDependencyGraph {
        DeclarationDependencyGraph(units: units)
    }

    private func tempRoot() -> String {
        NSTemporaryDirectory() + "kswk-cas-\(UUID().uuidString)"
    }

    // MARK: - Invalidation minimality

    @Test
    func bodyOnlyChangeInvalidatesOnlyThatDeclaration() {
        let old = graph(unit("a", refs: ["b"]), unit("b"), unit("c", refs: ["a"]))
        let new = graph(unit("a", refs: ["b"]), unit("b", body: "b2"), unit("c", refs: ["a"]))
        #expect(new.invalidated(since: old) == ["b"])
    }

    @Test
    func signatureChangeInvalidatesDirectDependentsOnly() {
        let old = graph(unit("a", refs: ["b"]), unit("b"), unit("c", refs: ["a"]))
        let new = graph(unit("a", refs: ["b"]), unit("b", sig: "s2"), unit("c", refs: ["a"]))
        #expect(new.invalidated(since: old) == ["a", "b"])
    }

    @Test
    func signatureChangePropagatesTransitivelyOnlyWhenDependentSignatureChanges() {
        let old = graph(unit("a", refs: ["b"]), unit("b"), unit("c", refs: ["a"]))
        let new = graph(unit("a", sig: "s2", refs: ["b"]), unit("b", sig: "s2"), unit("c", refs: ["a"]))
        #expect(new.invalidated(since: old) == ["a", "b", "c"])
    }

    @Test
    func addedDeclarationIsInvalidatedAndRemovalInvalidatesFormerCallers() {
        let old = graph(unit("a", refs: ["b"]), unit("b"))
        let added = graph(unit("a", refs: ["b"]), unit("b"), unit("z"))
        #expect(added.invalidated(since: old) == ["z"])
        let removed = graph(unit("a", refs: ["b"]))
        #expect(removed.invalidated(since: old) == ["a"])
    }

    @Test
    func unchangedGraphInvalidatesNothing() {
        let g = graph(unit("a", refs: ["b"]), unit("b"))
        #expect(g.invalidated(since: g).isEmpty)
    }

    // MARK: - Cache keys

    @Test
    func cacheKeyIgnoresBodiesOfReferencesButTracksTheirSignatures() {
        let base = graph(unit("a", refs: ["b"]), unit("b"))
        let bodyEdited = graph(unit("a", refs: ["b"]), unit("b", body: "b2"))
        let sigEdited = graph(unit("a", refs: ["b"]), unit("b", sig: "s2"))
        let key = base.cacheKey(for: "a", environment: "env")
        #expect(key == bodyEdited.cacheKey(for: "a", environment: "env"))
        #expect(key != sigEdited.cacheKey(for: "a", environment: "env"))
        #expect(key != base.cacheKey(for: "a", environment: "env2"))
        #expect(base.cacheKey(for: "missing", environment: "env") == nil)
    }

    @Test
    func makeKeyIsLengthPrefixed() {
        #expect(ContentAddressedStore.makeKey(parts: ["ab", "c"]) != ContentAddressedStore.makeKey(parts: ["a", "bc"]))
    }

    // MARK: - Store safety

    @Test
    func storeRoundTripsAndCountsStatistics() {
        let store = ContentAddressedStore(rootPath: tempRoot())
        let key = ContentAddressedStore.makeKey(parts: ["x"])
        #expect(store.load(key: key) == nil)
        #expect(store.store(key: key, payload: Data("obj".utf8)))
        #expect(store.contains(key: key))
        #expect(store.load(key: key) == Data("obj".utf8))
        #expect(store.statistics == .init(hits: 1, misses: 1, corrupted: 0, stores: 1))
    }

    @Test
    func corruptedEntryIsAMissAndIsRemoved() throws {
        let root = tempRoot()
        let store = ContentAddressedStore(rootPath: root)
        let key = ContentAddressedStore.makeKey(parts: ["y"])
        #expect(store.store(key: key, payload: Data("payload".utf8)))
        let path = "\(root)/\(key.prefix(2))/\(key)"
        var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: URL(fileURLWithPath: path))
        #expect(store.load(key: key) == nil)
        #expect(!store.contains(key: key))
        #expect(store.statistics.corrupted == 1)
        // Truncated entries are also rejected.
        #expect(store.store(key: key, payload: Data("payload".utf8)))
        try Data("KSW".utf8).write(to: URL(fileURLWithPath: path))
        #expect(store.load(key: key) == nil)
    }

    @Test
    func invalidKeysAreRejected() {
        let store = ContentAddressedStore(rootPath: tempRoot())
        #expect(!store.store(key: "../../etc/passwd", payload: Data()))
        #expect(store.load(key: "ABC") == nil)
    }

    @Test
    func symlinkedRootIsUntrusted() throws {
        let real = tempRoot()
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        let link = tempRoot()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        let store = ContentAddressedStore(rootPath: link)
        #expect(!store.store(key: ContentAddressedStore.makeKey(parts: ["z"]), payload: Data("p".utf8)))
    }
}
#endif
