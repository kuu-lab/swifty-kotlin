#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DependencyGraphTests {
    // MARK: - Basic mutation and query

    @Test
    func testRecordProvidedAndQuery() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo", "Bar"])
        #expect(graph.provided(by: "a.kt") == ["Foo", "Bar"])
    }

    @Test
    func testRecordDependedAndQuery() {
        let graph = DependencyGraph()
        graph.recordDepended(filePath: "b.kt", symbols: ["Baz"])
        #expect(graph.depended(by: "b.kt") == ["Baz"])
    }

    @Test
    func testProvidedReturnsEmptyForUnknownFile() {
        let graph = DependencyGraph()
        #expect(graph.provided(by: "unknown.kt") == [])
    }

    @Test
    func testDependedReturnsEmptyForUnknownFile() {
        let graph = DependencyGraph()
        #expect(graph.depended(by: "unknown.kt") == [])
    }

    // MARK: - trackedFiles

    @Test
    func testTrackedFilesReturnsSortedUnion() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "b.kt", symbols: ["B"])
        graph.recordDepended(filePath: "a.kt", symbols: ["A"])
        #expect(graph.trackedFiles == ["a.kt", "b.kt"])
    }

    @Test
    func testTrackedFilesReturnsEmptyWhenEmpty() {
        let graph = DependencyGraph()
        #expect(graph.trackedFiles == [])
    }

    // MARK: - recompilationSet

    @Test
    func testRecompilationSetWithEmptyChangedFiles() {
        let graph = DependencyGraph()
        let result = graph.recompilationSet(changedFiles: [], allFiles: ["a.kt"])
        #expect(result == [])
    }

    @Test
    func testRecompilationSetIncludesChangedFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        #expect(result.contains("a.kt"))
    }

    @Test
    func testRecompilationSetIncludesDependentFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])
        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        #expect(result == ["a.kt", "b.kt"])
    }

    @Test
    func testRecompilationSetTransitiveDependencies() {
        let graph = DependencyGraph()
        // a provides Foo, b depends on Foo and provides Bar, c depends on Bar
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordProvided(filePath: "b.kt", symbols: ["Bar"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "c.kt", symbols: ["Bar"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt", "c.kt"]
        )
        #expect(Set(result) == Set(["a.kt", "b.kt", "c.kt"]))
    }

    @Test
    func testRecompilationSetDoesNotIncludeUnrelatedFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Unrelated"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        #expect(result == ["a.kt"])
    }

    @Test
    func testRecompilationSetPreservesAllFilesOrder() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["X"])
        graph.recordDepended(filePath: "c.kt", symbols: ["X"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["c.kt", "b.kt", "a.kt"]
        )
        // Should preserve allFiles order
        #expect(result == ["c.kt", "a.kt"])
    }

    // MARK: - Serialization

    @Test
    func testSerializeAndDeserializeRoundTrip() throws {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo", "Bar"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])

        let data = try graph.serialize()
        let restored = try DependencyGraph.deserialize(from: data)

        #expect(restored.provided(by: "a.kt") == ["Foo", "Bar"])
        #expect(restored.depended(by: "b.kt") == ["Foo"])
        #expect(restored.trackedFiles == ["a.kt", "b.kt"])
    }

    @Test
    func testSerializeEmptyGraph() throws {
        let graph = DependencyGraph()
        let data = try graph.serialize()
        let restored = try DependencyGraph.deserialize(from: data)
        #expect(restored.trackedFiles == [])
    }

    @Test
    func testDeserializeInvalidDataThrows() {
        let invalidData = Data("not json".utf8)
        #expect(throws: (any Error).self) { try DependencyGraph.deserialize(from: invalidData) }
    }
}
#endif
