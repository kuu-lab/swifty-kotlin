#if canImport(Testing)
@testable import TestStdlibCache
import Dispatch
import Foundation
import Testing

/// A lock-guarded box for state shared across `DispatchQueue.concurrentPerform`
/// iterations. Swift 6's strict concurrency checking flags mutation of a
/// captured `var` from concurrently-executing code even when it is guarded by
/// a manual `NSLock`, since it cannot see through the lock discipline — so
/// the mutable state has to live behind a `Sendable`-asserting reference type
/// instead of a captured local.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value {
        withLock { $0 }
    }
}

/// Regression coverage for `TestStdlibCache`'s content-addressed artifact
/// resolution. This replaced an earlier design that kept one fixed artifact
/// path plus an mtime/size "staleness" check, deleting and rebuilding that
/// path in place whenever the check said stale — including whenever it
/// couldn't resolve the running test binary's fingerprint at all, which it
/// treated as unconditionally stale. A worker that had already been handed
/// that fixed path by an earlier, already-returned `prepare()` call (in this
/// process or another one sharing the same `.build` directory) could then
/// observe a partially deleted or partially rebuilt directory while reading
/// it, with no lock protecting readers.
///
/// Content addressing (`TestStdlibCache.resolveOrBuildArtifact`) removes the
/// delete entirely: a given content key's path, once populated by the atomic
/// rename at the end of a build, is never touched again by this type.
@Suite
struct TestStdlibCacheContentAddressingTests {
    private func withTempBuildDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestStdlibCacheContentAddressingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    /// Stands in for `StdlibArtifactBuilder.build`: creates a directory at
    /// `outputBase + ".kklib"` containing a marker file, and returns that
    /// path, matching the real builder's contract without the multi-second
    /// real stdlib compile.
    private func fakeBuild(outputBase: String, marker: String) throws -> String {
        let artifactPath = outputBase + ".kklib"
        try FileManager.default.createDirectory(atPath: artifactPath, withIntermediateDirectories: true)
        try marker.write(toFile: artifactPath + "/marker.txt", atomically: true, encoding: .utf8)
        return artifactPath
    }

    @Test
    func identicalImageContentsReuseFingerprintButSameMetadataChangesDoNot() throws {
        try withTempBuildDirectory { buildDir in
            let fm = FileManager.default
            let image = buildDir.appendingPathComponent("CompilerBackendTests")
            let originalTime = Date(timeIntervalSince1970: 1_700_000_000)
            try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
            try Data("compiler-a".utf8).write(to: image)
            try fm.setAttributes([.modificationDate: originalTime], ofItemAtPath: image.path)
            let first = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))

            // A timestamp-only relink does not change the generated artifact.
            try fm.setAttributes([.modificationDate: originalTime.addingTimeInterval(10)], ofItemAtPath: image.path)
            let touched = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))
            #expect(touched == first)

            // Different bytes must invalidate even if size and timestamp match.
            try Data("compiler-b".utf8).write(to: image)
            try fm.setAttributes([.modificationDate: originalTime], ofItemAtPath: image.path)
            let changed = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))
            #expect(changed != first)

            let firstKey = try TestStdlibCache.contentKey(manifestHash: "same-stdlib", compilerFingerprint: first)
            let touchedKey = try TestStdlibCache.contentKey(manifestHash: "same-stdlib", compilerFingerprint: touched)
            let changedKey = try TestStdlibCache.contentKey(manifestHash: "same-stdlib", compilerFingerprint: changed)
            #expect(firstKey == touchedKey)
            #expect(firstKey != changedKey)

            var builds = 0
            func resolve(_ key: String) throws -> String {
                try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: key) {
                    builds += 1
                    return try fakeBuild(outputBase: $0, marker: "build-\(builds)")
                }
            }
            let firstArtifact = try resolve(firstKey)
            #expect(try resolve(touchedKey) == firstArtifact)
            #expect(builds == 1)
            #expect(try resolve(changedKey) != firstArtifact)
            #expect(builds == 2)
        }
    }

    @Test
    func runningTestProductHasACompilerFingerprint() throws {
        let image = try #require(TestStdlibCache.currentCompilerImageURL())
        let name = image.lastPathComponent
        // swiftbuild's KSwiftKPackageTests is a virtual aggregate that launches
        // the per-target image; native builds link a real aggregate executable.
        if let product = ProcessInfo.processInfo.environment["SWIFT_TEST_PRODUCT"],
           !product.isEmpty, product != "KSwiftKPackageTests" {
            #expect(name.hasPrefix(product))
        } else {
            #expect(name.hasPrefix("CompilerBackendTests") || name.hasPrefix("KSwiftKPackageTests"))
        }
        let fingerprint = try #require(TestStdlibCache.currentCompilerFingerprint())
        #expect(fingerprint.contains(image.path))
        _ = try TestStdlibCache.contentKey(manifestHash: "unchanged-kotlin", compilerFingerprint: fingerprint)
    }

    @Test(arguments: [
        "debug/KSwiftKPackageTests.xctest/Contents/MacOS/KSwiftKPackageTests",
        "arm64-apple-macosx/debug/KSwiftKPackageTests.xctest/Contents/MacOS/KSwiftKPackageTests",
        "out/Products/Debug/CompilerBackendTests.xctest/Contents/MacOS/CompilerBackendTests",
        "out/Products/Debug/CompilerCoreTests.xctest/Contents/MacOS/CompilerCoreTests",
        "x86_64-unknown-linux-gnu/debug/KSwiftKPackageTests.xctest",
        "aarch64-unknown-linux-gnu/debug/CompilerBackendTests-test-runner",
    ])
    func compilerRebuildChangesKeyAndPreservesPreviousArtifact(imagePath: String) throws {
        try withTempBuildDirectory { buildDir in
            let fm = FileManager.default
            let image = buildDir.appendingPathComponent(imagePath)
            try fm.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("compiler-before".utf8).write(to: image)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: image.path)

            let before = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))
            let beforeKey = try TestStdlibCache.contentKey(manifestHash: "unchanged-kotlin", compilerFingerprint: before)
            var buildCount = 0
            let beforeArtifact = try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: beforeKey) {
                buildCount += 1
                return try fakeBuild(outputBase: $0, marker: "before")
            }
            let reader = try FileHandle(forReadingFrom: URL(fileURLWithPath: beforeArtifact + "/marker.txt"))
            defer { try? reader.close() }

            // Model a Swift-only rebuild with unchanged bundled Kotlin sources
            // and the same binary size, but a later link time.
            try Data("compiler-after!".utf8).write(to: image)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_001)], ofItemAtPath: image.path)
            let after = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))
            let afterKey = try TestStdlibCache.contentKey(manifestHash: "unchanged-kotlin", compilerFingerprint: after)
            #expect(beforeKey != afterKey)
            let afterArtifact = try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: afterKey) {
                buildCount += 1
                return try fakeBuild(outputBase: $0, marker: "after")
            }
            let reusedArtifact = try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: afterKey) {
                buildCount += 1
                return try fakeBuild(outputBase: $0, marker: "unexpected-rebuild")
            }

            #expect(buildCount == 2)
            #expect(beforeArtifact != afterArtifact)
            #expect(afterArtifact == reusedArtifact)
            #expect(try String(contentsOfFile: beforeArtifact + "/marker.txt", encoding: .utf8) == "before")
            #expect(try String(contentsOfFile: afterArtifact + "/marker.txt", encoding: .utf8) == "after")
            #expect(String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self) == "before")
        }
    }

    @Test
    func missingLoadedImageCannotReuseAnUnknownKey() throws {
        try withTempBuildDirectory { buildDir in
            // An old aggregate product must not substitute for an unidentified
            // loaded per-target image, even when that old binary still exists.
            let staleImage = buildDir.appendingPathComponent("debug/KSwiftKPackageTests.xctest")
            try FileManager.default.createDirectory(at: staleImage.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("stale-aggregate".utf8).write(to: staleImage)
            #expect(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: nil) == nil)
            let missingImage = buildDir.appendingPathComponent("out/Products/Debug/missing")
            let fingerprint = TestStdlibCache.currentCompilerFingerprint(compilerImageURL: missingImage)
            #expect(fingerprint == nil)
            // Preserve the exact legacy key from KUU-1957's unknown-fingerprint
            // reproducer. An existing artifact at that key is never reusable
            // when the loaded compiler identity is unavailable.
            let legacyPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir, contentKey: "aa49fee9d5845dca"
            ) { try fakeBuild(outputBase: $0, marker: "legacy-unknown") }
            var builderRan = false
            #expect(throws: (any Error).self) {
                try TestStdlibCache.resolveOrBuildArtifact(
                    buildDirectory: buildDir,
                    contentKey: TestStdlibCache.contentKey(manifestHash: "2c03971e8e2e5468", compilerFingerprint: fingerprint)
                ) {
                    builderRan = true
                    return try fakeBuild(outputBase: $0, marker: "unexpected")
                }
            }
            #expect(!builderRan)
            #expect(try String(contentsOfFile: legacyPath + "/marker.txt", encoding: .utf8) == "legacy-unknown")
            #expect(throws: (any Error).self) {
                try TestStdlibCache.contentKey(manifestHash: "unchanged-kotlin", compilerFingerprint: "")
            }
        }
    }

    @Test
    func secondResolveForTheSameKeyReusesWithoutRebuilding() throws {
        try withTempBuildDirectory { buildDir in
            var buildCount = 0
            let firstPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-a"
            ) { outputBase in
                buildCount += 1
                return try fakeBuild(outputBase: outputBase, marker: "first-build")
            }

            let secondPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-a"
            ) { outputBase in
                buildCount += 1
                Issue.record("builder should not run again for an already-resolved content key")
                return try fakeBuild(outputBase: outputBase, marker: "second-build")
            }

            #expect(firstPath == secondPath)
            #expect(buildCount == 1)
            let content = try String(contentsOfFile: firstPath + "/marker.txt", encoding: .utf8)
            #expect(content == "first-build")
        }
    }

    @Test
    func resolvingADifferentKeyNeverTouchesAnExistingArtifact() throws {
        try withTempBuildDirectory { buildDir in
            let keyAPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-a"
            ) { outputBase in try fakeBuild(outputBase: outputBase, marker: "key-a-marker") }

            // A process that resolves a different content key — e.g. because
            // it computed a different (or unresolvable) compiler fingerprint —
            // must never delete or replace key-a's already-resolved artifact.
            let keyBPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-b"
            ) { outputBase in try fakeBuild(outputBase: outputBase, marker: "key-b-marker") }

            #expect(keyAPath != keyBPath)
            #expect(FileManager.default.fileExists(atPath: keyAPath))
            let keyAMarker = try String(contentsOfFile: keyAPath + "/marker.txt", encoding: .utf8)
            #expect(keyAMarker == "key-a-marker")
            let keyBMarker = try String(contentsOfFile: keyBPath + "/marker.txt", encoding: .utf8)
            #expect(keyBMarker == "key-b-marker")
        }
    }

    /// The direct regression test: an open reader on an already-resolved
    /// artifact must keep working across a later `resolveOrBuildArtifact`
    /// call for the same key, exactly as a `GoldenHarnessWorker` subprocess
    /// mid-read of the shared `.kklib` must keep working across another
    /// process's `prepare()` call.
    @Test
    func existingArtifactStaysReadableAcrossALaterResolveForTheSameKey() throws {
        try withTempBuildDirectory { buildDir in
            let firstPath = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-a"
            ) { outputBase in try fakeBuild(outputBase: outputBase, marker: "stable-content") }

            let markerURL = URL(fileURLWithPath: firstPath + "/marker.txt")
            let handle = try FileHandle(forReadingFrom: markerURL)
            defer { try? handle.close() }

            _ = try TestStdlibCache.resolveOrBuildArtifact(
                buildDirectory: buildDir,
                contentKey: "key-a"
            ) { outputBase in
                Issue.record("builder should not run again for an already-resolved content key")
                return try fakeBuild(outputBase: outputBase, marker: "should-not-happen")
            }

            let data = try handle.readToEnd() ?? Data()
            #expect(String(decoding: data, as: UTF8.self) == "stable-content")
        }
    }

    @Test
    func concurrentResolvesForTheSameKeyBuildExactlyOnce() throws {
        try withTempBuildDirectory { buildDir in
            let buildCount = LockedBox(0)
            let resolvedPaths = LockedBox<[String]>([])
            let caughtErrors = LockedBox<[String]>([])

            let iterations = 8
            DispatchQueue.concurrentPerform(iterations: iterations) { _ in
                do {
                    let path = try TestStdlibCache.resolveOrBuildArtifact(
                        buildDirectory: buildDir,
                        contentKey: "key-concurrent"
                    ) { outputBase in
                        buildCount.withLock { $0 += 1 }
                        // Give other concurrent callers a chance to reach the
                        // lock while this one is still "building", so the
                        // test actually exercises the serialization instead
                        // of finishing before anyone else starts.
                        Thread.sleep(forTimeInterval: 0.05)
                        return try fakeBuild(outputBase: outputBase, marker: "concurrent-build")
                    }
                    resolvedPaths.withLock { $0.append(path) }
                } catch {
                    caughtErrors.withLock { $0.append(String(describing: error)) }
                }
            }

            #expect(caughtErrors.current.isEmpty)
            #expect(buildCount.current == 1)
            #expect(Set(resolvedPaths.current).count == 1)
            #expect(resolvedPaths.current.count == iterations)
        }
    }
}
#endif
