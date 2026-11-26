#if canImport(Testing)
@testable import TestStdlibCache
import Dispatch
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

@Suite
struct TestStdlibCacheContentAddressingTests {
    private func withTempBuildDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestStdlibCacheContentAddressingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

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

            try fm.setAttributes([.modificationDate: originalTime.addingTimeInterval(10)], ofItemAtPath: image.path)
            let touched = try #require(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: image))
            #expect(touched == first)

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
            let staleImage = buildDir.appendingPathComponent("debug/KSwiftKPackageTests.xctest")
            try FileManager.default.createDirectory(at: staleImage.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("stale-aggregate".utf8).write(to: staleImage)
            #expect(TestStdlibCache.currentCompilerFingerprint(compilerImageURL: nil) == nil)
            let missingImage = buildDir.appendingPathComponent("out/Products/Debug/missing")
            let fingerprint = TestStdlibCache.currentCompilerFingerprint(compilerImageURL: missingImage)
            #expect(fingerprint == nil)
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
    func missingFingerprintErrorCarriesTheIdentityFailureDetail() {
        do {
            _ = try TestStdlibCache.contentKey(
                manifestHash: "unchanged-kotlin",
                compilerFingerprint: nil,
                failureDetail: "no usable libLLVM could be loaded"
            )
            Issue.record("expected contentKey to reject a missing fingerprint")
        } catch {
            #expect(String(describing: error).contains("no usable libLLVM could be loaded"))
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
    func interruptedAttemptCannotShareTheNextAttemptStagingPath() throws {
        enum Interrupted: Error { case stopped }
        try withTempBuildDirectory { buildDir in
            let fm = FileManager.default
            var previousPath = ""
            #expect(throws: Interrupted.self) {
                try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: "same-key") { output in
                    previousPath = try fakeBuild(outputBase: output, marker: "old-worker")
                    throw Interrupted.stopped
                }
            }
            let published = try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: "same-key") { output in
                #expect(output + ".kklib" != previousPath)
                #expect(fm.fileExists(atPath: previousPath))
                return try fakeBuild(outputBase: output, marker: "new-worker")
            }
            try "orphan-write".write(toFile: previousPath + "/marker.txt", atomically: true, encoding: .utf8)
            #expect(try String(contentsOfFile: published + "/marker.txt", encoding: .utf8) == "new-worker")
        }
    }

    @Test
    func staleStagingIsRemovedOnlyAfterItsAttemptLockIsReleased() throws {
        try withTempBuildDirectory { buildDir in
            let fm = FileManager.default
            try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
            let artifactName = "kswiftk-test-stdlib-cache-example.kklib"
            let base = buildDir.appendingPathComponent(artifactName + ".building-1-fixture")
            let staging = URL(fileURLWithPath: base.path + ".kklib")
            let lockPath = base.path + ".lock"
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let fd = lockPath.withCString { open($0, O_CREAT | O_RDWR, 0o600) }
            #expect(fd >= 0)
            guard fd >= 0 else { return }
            defer { close(fd) }
            #expect(flock(fd, LOCK_SH) == 0)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: lockPath)
            TestStdlibCache.cleanupStaleStaging(buildDirectory: buildDir, olderThan: Date())
            #expect(fm.fileExists(atPath: staging.path))
            #expect(flock(fd, LOCK_UN) == 0)
            _ = try TestStdlibCache.resolveOrBuildArtifact(buildDirectory: buildDir, contentKey: "different-key") { output in
                try fakeBuild(outputBase: output, marker: "new-key")
            }
            #expect(!fm.fileExists(atPath: staging.path))
            #expect(fm.fileExists(atPath: lockPath))
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
