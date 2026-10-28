#if canImport(Darwin)
@testable import TestStdlibCache
@testable import CompilerBackend
import CompilerCore
import Foundation
import Testing

@Suite
struct TestStdlibWorkerProvenanceTests {
    @Test
    func testRequestIdsDoNotInvalidateCompilerEnvironment() {
        let original = ["CODEX_TOOL_CALL_ID": "first", "KSWIFTK_TEST_STDLIB_PROVENANCE": "one", "SDKROOT": "/sdk"]
        let next = ["CODEX_TOOL_CALL_ID": "second", "KSWIFTK_TEST_STDLIB_PROVENANCE": "two", "SDKROOT": "/sdk"]
        let changed = ["CODEX_TOOL_CALL_ID": "second", "KSWIFTK_TEST_STDLIB_PROVENANCE": "two", "SDKROOT": "/other"]
        #expect(TestStdlibCompilerIdentity.environmentFingerprint(original) == TestStdlibCompilerIdentity.environmentFingerprint(next))
        #expect(TestStdlibCompilerIdentity.environmentFingerprint(original) != TestStdlibCompilerIdentity.environmentFingerprint(changed))
    }

    @Test
    func fallbackFingerprintIncludesCompilerContext() throws {
        let image = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: image) }
        try Data("test-image".utf8).write(to: image)
        let first = try #require(TestStdlibWorkerProvenance.fullImageFingerprint(imageURL: image, context: "llvm-a"))
        let second = try #require(TestStdlibWorkerProvenance.fullImageFingerprint(imageURL: image, context: "llvm-b"))
        #expect(first != second)
        #expect(TestStdlibWorkerProvenance.fullImageFingerprint(imageURL: image, context: nil) == nil)
    }

    @Test
    func linuxExecutableMappingsRejectDeletedOrUnidentifiableCode() {
        let maps = """
        1000-2000 r--p 00000000 00:00 1 /tmp/data
        2000-3000 r-xp 00001000 00:00 1 /tmp/lib with spaces.so
        3000-4000 r-xp 00000000 00:00 0 [vdso]
        """
        #expect(TestStdlibCompilerIdentity.linuxExecutableMappings(maps) == ["/tmp/lib with spaces.so"])
        #expect(TestStdlibCompilerIdentity.linuxExecutableMappings(maps + "\n4000-5000 r-xp 0 00:00 2 /tmp/old.so (deleted)") == nil)
        #expect(TestStdlibCompilerIdentity.linuxExecutableMappings(maps + "\n4000-5000 r-xp 0 00:00 0") == nil)
    }

    @Test
    func acceptsOnlyTheAttestedImageWorkerAndCompilerContext() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build")
        let records = root.appendingPathComponent("kswiftk-test-provenance")
        let products = root.appendingPathComponent("out/Products/Debug")
        try fm.createDirectory(at: records, withIntermediateDirectories: true)
        try fm.createDirectory(at: products, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let marker = records.appendingPathComponent("pending-\(id).json")
        let image = records.appendingPathComponent("image-fixture-\(id)")
        let worker = products.appendingPathComponent(".kswiftk-test-stdlib-worker-fixture-\(id)")
        defer {
            try? fm.removeItem(at: marker)
            try? fm.removeItem(at: image)
            try? fm.removeItem(at: worker)
        }

        let context = try #require(TestStdlibCompilerIdentity.current())
        try Data("test-image-a".utf8).write(to: image)
        try "#!/bin/sh\nprintf '%s\\n' '\(context)'\n".write(to: worker, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
        let imageHash = try #require(TestStdlibWorkerProvenance.stableFileHash(image.path))
        let workerHash = try #require(TestStdlibWorkerProvenance.stableFileHash(worker.path))
        let data = try JSONSerialization.data(withJSONObject: [
            "state": "ready", "imageHash": imageHash, "inputsHash": String(repeating: "a", count: 64),
            "workerPath": worker.path, "workerHash": workerHash,
        ])
        try data.write(to: marker)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        let originalWorker = try #require(TestStdlibWorkerProvenance.resolve(markerPath: marker.path, imageURL: image, waitSeconds: 1))
        let changedInputs = try JSONSerialization.data(withJSONObject: [
            "state": "ready", "imageHash": imageHash, "inputsHash": String(repeating: "b", count: 64),
            "workerPath": worker.path, "workerHash": workerHash,
        ])
        try changedInputs.write(to: marker)
        let nextWorker = try #require(TestStdlibWorkerProvenance.resolve(markerPath: marker.path, imageURL: image, waitSeconds: 1))
        #expect(originalWorker.fingerprint != nextWorker.fingerprint)
        try data.write(to: marker)

        let fixedDate = Date(timeIntervalSince1970: 1_600_000_000)
        try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: image.path)
        try Data("test-image-b".utf8).write(to: image)
        try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: image.path)
        #expect(TestStdlibWorkerProvenance.resolve(markerPath: marker.path, imageURL: image, waitSeconds: 1) == nil)

        try Data("test-image-a".utf8).write(to: image)
        let workerContents = try Data(contentsOf: worker)
        try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: worker.path)
        var changed = workerContents
        changed[changed.startIndex] ^= 1
        try changed.write(to: worker)
        try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: worker.path)
        #expect(TestStdlibWorkerProvenance.resolve(markerPath: marker.path, imageURL: image, waitSeconds: 1) == nil)

        if ProcessInfo.processInfo.environment["KSWIFTK_TEST_STDLIB_WORKER_E2E"] == "1" {
            let active = try #require(TestStdlibWorkerProvenance.resolve())
            TestStdlibCache.shared.prepare()
            let artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
            #expect(artifact.hasSuffix(".kklib"))
            #expect(fm.fileExists(atPath: artifact))
            #expect(artifact.hasPrefix(root.path + "/"))
            #expect(fm.isReadableFile(atPath: artifact + "/manifest.json"))
            let manifest = try Data(contentsOf: URL(fileURLWithPath: artifact + "/manifest.json"))
            #expect(!manifest.isEmpty)
            let decoded = try JSONSerialization.jsonObject(with: manifest)
            let manifestObject = try #require(decoded as? [String: Any])
            #expect(manifestObject["libraryKind"] as? String == "stdlib")
            let stdlibHash = try #require(manifestObject["stdlibManifestHash"] as? String)
            #expect(!stdlibHash.isEmpty)
            let objects = try #require(manifestObject["objects"] as? [String])
            #expect(!objects.isEmpty)
            #expect(objects.allSatisfy { $0.hasSuffix(".o") })
            print("TEST_STDLIB_WORKER=\(active.path)")
            print("TEST_STDLIB_ARTIFACT=\(artifact)")
        }
    }
}
#endif
