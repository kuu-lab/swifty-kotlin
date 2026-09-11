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
