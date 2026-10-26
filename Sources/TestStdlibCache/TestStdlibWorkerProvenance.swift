import CompilerBackend
import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A build-wrapper attestation binds the running test image to an isolated
/// worker linked from the same unchanged compiler objects.
enum TestStdlibWorkerProvenance {
    struct Record: Decodable {
        let state: String
        let imageHash: String?
        let inputsHash: String?
        let workerPath: String?
        let workerHash: String?
    }

    struct Worker {
        let path: String
        let fingerprint: String
        let hash: String
        let context: String
    }

    static func resolve(
        markerPath: String? = ProcessInfo.processInfo.environment["KSWIFTK_TEST_STDLIB_PROVENANCE"],
        imageURL: URL? = TestStdlibCache.currentCompilerImageURL(),
        waitSeconds: TimeInterval = ProcessInfo.processInfo.environment["KSWIFTK_TEST_STDLIB_PROVENANCE_WAIT"]
            .flatMap { TimeInterval($0) }.flatMap { $0 > 0 && $0 <= 600 ? $0 : nil } ?? 15
    ) -> Worker? {
        #if canImport(Darwin)
        guard let markerPath, let imageURL else { return nil }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true).standardizedFileURL.path
        let marker = URL(fileURLWithPath: markerPath).standardizedFileURL.path
        guard marker.hasPrefix(root + "/kswiftk-test-provenance/pending-") else { return nil }
        let request = marker + ".request-\(UUID().uuidString)"
        guard FileManager.default.createFile(atPath: request, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(atPath: request) }
        let deadline = Date().addingTimeInterval(waitSeconds)
        while Date() < deadline {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: marker),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let permissions = (attrs[.posixPermissions] as? NSNumber)?.uint16Value,
                  permissions & 0o077 == 0,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: marker)),
                  let record = try? JSONDecoder().decode(Record.self, from: data)
            else { return nil }
            if record.state == "pending" {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            guard record.state == "ready", let expectedImage = record.imageHash,
                  let inputs = record.inputsHash, inputs.utf8.count == 64,
                  inputs.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  let path = record.workerPath, let expectedWorker = record.workerHash,
                  path.hasPrefix(root + "/out/Products/Debug/.kswiftk-test-stdlib-worker-"),
                  URL(fileURLWithPath: path).standardizedFileURL.path == path,
                  FileManager.default.isExecutableFile(atPath: path),
                  let actualImage = stableFileHash(imageURL.path), actualImage == expectedImage,
                  let actualWorker = stableFileHash(path), actualWorker == expectedWorker,
                  let context = TestStdlibCompilerIdentity.current(),
                  let result = try? CommandRunner.run(executable: path, arguments: ["--identity"], timeout: 60),
                  result.exitCode == 0,
                  result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == context,
                  stableFileHash(path) == expectedWorker
            else { return nil }
            return Worker(path: path, fingerprint: "worker-v2|\(expectedWorker)|\(inputs)|\(context)", hash: expectedWorker, context: context)
        }
        return nil
        #else
        return nil
        #endif
    }

    static func stableFileHash(_ path: String) -> String? {
        let fm = FileManager.default
        guard let before = try? fm.attributesOfItem(atPath: path),
              before[.type] as? FileAttributeType == .typeRegular,
              let changeBefore = fileChangeTime(path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        else { return nil }
        let digest = FileFingerprint.compute(for: path, contents: data).contentHash
        guard let changeAfter = fileChangeTime(path), changeBefore.0 == changeAfter.0,
              changeBefore.1 == changeAfter.1,
              let after = try? fm.attributesOfItem(atPath: path),
              (before[.size] as? NSNumber) == (after[.size] as? NSNumber),
              (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),
              (before[.systemFileNumber] as? NSNumber) == (after[.systemFileNumber] as? NSNumber)
        else { return nil }
        return digest
    }

    static func fullImageFingerprint(imageURL: URL?, context: String?) -> String? {
        guard let imageURL, let context, !context.isEmpty,
              let digest = stableFileHash(imageURL.path) else { return nil }
        return "loaded-image-v3|\(imageURL.path)|\(digest)|\(context)"
    }

    private static func fileChangeTime(_ path: String) -> (Int64, Int64)? {
        #if canImport(Darwin)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec))
        #elseif canImport(Glibc)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (Int64(info.st_ctim.tv_sec), Int64(info.st_ctim.tv_nsec))
        #else
        return nil
        #endif
    }

    static func build(worker: Worker, outputBase: String) throws -> String {
        guard stableFileHash(worker.path) == worker.hash,
              TestStdlibCompilerIdentity.current() == worker.context else {
            throw WorkerError.invalidOutput
        }
        let result = try CommandRunner.run(
            executable: worker.path, arguments: ["--build", outputBase, worker.context], timeout: 900
        )
        guard result.exitCode == 0, stableFileHash(worker.path) == worker.hash,
              TestStdlibCompilerIdentity.current() == worker.context else {
            throw WorkerError.buildFailed(result.stderr)
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path == outputBase + ".kklib" else { throw WorkerError.invalidOutput }
        return path
    }

    enum WorkerError: Error {
        case buildFailed(String)
        case invalidOutput
    }
}
