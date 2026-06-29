#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IncrementalCompilationCacheTests {
    private var tempDir: String

    init() {
        tempDir = NSTemporaryDirectory() + "IncrementalCacheTest_\(UUID().uuidString)"
    }

    // MARK: - Init

    @Test
    func testInitSetsPath() {
        let cache = IncrementalCompilationCache(cachePath: "/some/path")
        #expect(cache.cachePath == "/some/path")
    }

    // MARK: - hasPreviousCache

    @Test
    func testHasPreviousCacheReturnsFalseInitially() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        #expect(!(cache.hasPreviousCache))
    }

    // MARK: - dependencyGraph

    @Test
    func testDependencyGraphIsNilInitially() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        #expect(cache.dependencyGraph == nil)
    }

    // MARK: - loadPreviousState with no files

    @Test
    func testLoadPreviousStateWithNoCacheDir() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.loadPreviousState()
        #expect(!(cache.hasPreviousCache))
        #expect(cache.dependencyGraph == nil)
    }

    // MARK: - Save and load round-trip

    @Test
    func testSaveAndLoadRoundTrip() throws {
        let cache = IncrementalCompilationCache(cachePath: tempDir)

        // Write a temp source file
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        // Compute fingerprints and save
        cache.computeCurrentFingerprints(for: [sourceFile])

        let graph = DependencyGraph()
        graph.recordProvided(filePath: sourceFile, symbols: ["main"])
        cache.saveState(dependencyGraph: graph)

        // Load into a new cache instance
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        #expect(cache2.hasPreviousCache)
        #expect(cache2.dependencyGraph != nil)
    }

    // MARK: - changedFiles

    @Test
    func testChangedFilesDetectsNewFile() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        // No previous state loaded — all files are new
        cache.computeCurrentFingerprints(for: [sourceFile])
        let changed = cache.changedFiles(allPaths: [sourceFile])
        #expect(changed.contains(sourceFile))
    }

    @Test
    func testChangedFilesDetectsContentChange() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"

        // First build — compute fingerprints from known contents directly
        let contents1 = Data("fun main() {}".utf8)
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        // Write file so compute works
        try contents1.write(to: URL(fileURLWithPath: sourceFile))
        cache1.computeCurrentFingerprints(for: [sourceFile])
        let graph = DependencyGraph()
        cache1.saveState(dependencyGraph: graph)

        // Modify the file with different content and ensure mtime changes
        Thread.sleep(forTimeInterval: 0.05)
        let contents2 = Data("fun main() { println(\"changed\") }".utf8)
        try contents2.write(to: URL(fileURLWithPath: sourceFile))

        // Second build
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let changed = cache2.changedFiles(allPaths: [sourceFile])
        #expect(changed.contains(sourceFile))
    }

    @Test
    func testChangedFilesDetectsContentChangeWhenMTimeIsUnchanged() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"

        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [sourceFile])
        cache1.saveState(dependencyGraph: DependencyGraph())
        let originalMTime = try #require(
            FileManager.default.attributesOfItem(atPath: sourceFile)[.modificationDate] as? Date
        )

        try "fun main() { println(\"changed\") }".write(toFile: sourceFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: originalMTime], ofItemAtPath: sourceFile)

        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let changed = cache2.changedFiles(allPaths: [sourceFile])
        #expect(changed.contains(sourceFile))
    }

    @Test
    func testChangedFilesDetectsRemovedFile() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let fileA = sourceDir + "/a.kt"
        let fileB = sourceDir + "/b.kt"

        // First build with two files
        try "fun a() {}".write(toFile: fileA, atomically: true, encoding: .utf8)
        try "fun b() {}".write(toFile: fileB, atomically: true, encoding: .utf8)
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [fileA, fileB])
        cache1.saveState(dependencyGraph: DependencyGraph())

        // Second build with only one file
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [fileA])
        let changed = cache2.changedFiles(allPaths: [fileA])
        // fileB was in previous build but not in current — should be in changed
        #expect(changed.contains(fileB))
    }

    // MARK: - recompilationSet

    @Test
    func testRecompilationSetReturnsNilWithoutPreviousCache() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        let result = cache.recompilationSet(allPaths: ["/a.kt"])
        #expect(result == nil)
    }

    @Test
    func testRecompilationSetReturnsNilWithoutDependencyGraph() throws {
        // Save state with fingerprints but corrupt the deps.json
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [sourceFile])
        cache1.saveState(dependencyGraph: DependencyGraph())

        // Corrupt deps.json
        try "invalid".write(toFile: tempDir + "/deps.json", atomically: true, encoding: .utf8)

        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let result = cache2.recompilationSet(allPaths: [sourceFile])
        #expect(result == nil)
    }

    @Test
    func testRecompilationSetReturnsEmptyWhenNothingChanged() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        // First build
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [sourceFile])
        let graph = DependencyGraph()
        graph.recordProvided(filePath: sourceFile, symbols: ["main"])
        cache1.saveState(dependencyGraph: graph)

        // Second build — no changes
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let result = cache2.recompilationSet(allPaths: [sourceFile])
        #expect(result != nil)
        #expect(try #require(result?.isEmpty))
    }

    // MARK: - loadPreviousState with unsupported manifest version

    @Test
    func testLoadPreviousStateIgnoresUnsupportedManifestVersion() throws {
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let manifest = "{\"version\": 999, \"fingerprints\": []}"
        try manifest.write(toFile: tempDir + "/manifest.json", atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.loadPreviousState()
        #expect(!(cache.hasPreviousCache))
    }

    // MARK: - computeCurrentFingerprints with SourceManager

    @Test
    func testComputeCurrentFingerprintsWithSourceManager() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let sm = SourceManager()
        _ = sm.addFile(path: sourceFile, contents: Data("fun main() {}".utf8))

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.computeCurrentFingerprints(for: [sourceFile], sourceManager: sm)
        // File should be considered new (no previous cache)
        let changed = cache.changedFiles(allPaths: [sourceFile])
        #expect(changed.contains(sourceFile))
    }

    @Test
    func testComputeCurrentFingerprintsFallsBackToFileSystemWhenNotInSourceManager() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let sm = SourceManager()
        // Do NOT add the file to SourceManager — force fallback

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.computeCurrentFingerprints(for: [sourceFile], sourceManager: sm)
        let changed = cache.changedFiles(allPaths: [sourceFile])
        #expect(changed.contains(sourceFile))
    }
}
#endif
