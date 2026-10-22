@testable import CompilerBackend
import Foundation
import Testing

struct MacOSPrelinkedObjectsTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeInputs(_ count: Int, in directory: URL) throws -> [String] {
        try (0..<count).map { index in
            let url = directory.appendingPathComponent("input-\(index).o")
            try Data("object-\(index)".utf8).write(to: url)
            return url.path
        }
    }

    private func makeDriver(in directory: URL) throws -> String {
        let driver = directory.appendingPathComponent("clang")
        try Data("driver".utf8).write(to: driver)
        return driver.path
    }

    @Test
    func skipsInputSetsThatCannotShrink() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let driver = try makeDriver(in: directory)
        for inputs in [[String](), ["a.o"], ["a.o", "b.o"]] {
            var builds = 0
            #expect(MacOSPrelinkedObjects.resolve(
                inputs: inputs, cacheDirectory: directory, driver: driver,
                target: "arm64-apple-macosx11.0", environment: [:],
                build: { _, _ in builds += 1 }
            ) == nil)
            #expect(builds == 0)
        }
    }

    @Test
    func honorsDisableEnvironmentVariable() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputs = try makeInputs(3, in: directory)
        var builds = 0
        #expect(MacOSPrelinkedObjects.resolve(
            inputs: inputs, cacheDirectory: directory,
            driver: try makeDriver(in: directory), target: "arm64-apple-macosx11.0",
            environment: ["KSWIFTK_NO_LINK_PRELINK": "1"],
            build: { _, _ in builds += 1 }
        ) == nil)
        #expect(builds == 0)
    }

    @Test
    func cachesMergedObjectAndInvalidatesOnInputChange() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let driver = try makeDriver(in: directory)
        var inputs = try makeInputs(3, in: directory)

        var builds = 0
        func resolve() -> String? {
            MacOSPrelinkedObjects.resolve(
                inputs: inputs, cacheDirectory: cache, driver: driver,
                target: "arm64-apple-macosx11.0", environment: [:]
            ) { _, temporary in
                builds += 1
                try Data("merged".utf8).write(to: temporary)
            }
        }

        let first = try #require(resolve())
        let second = try #require(resolve())
        #expect(first == second)
        #expect(builds == 1)
        #expect(first.hasPrefix(cache.path))
        #expect(FileManager.default.fileExists(atPath: first))

        // A missing input fails the whole resolve rather than merging a subset.
        inputs.append(directory.appendingPathComponent("missing.o").path)
        #expect(resolve() == nil)
        inputs.removeLast()

        // Content change on any input produces a freshly built object.
        try Data("object-0-changed".utf8)
            .write(to: URL(fileURLWithPath: inputs[0]))
        let third = try #require(resolve())
        #expect(third != first)
        #expect(builds == 2)
    }

    @Test
    func fallsBackWhenPartialLinkFails() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let inputs = try makeInputs(3, in: directory)
        struct BuildFailure: Error {}
        #expect(MacOSPrelinkedObjects.resolve(
            inputs: inputs, cacheDirectory: cache,
            driver: try makeDriver(in: directory), target: "arm64-apple-macosx11.0",
            environment: [:],
            build: { _, _ in throw BuildFailure() }
        ) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    }

    @Test
    func rejectsUntrustedCacheDirectory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: cache.path)
        let inputs = try makeInputs(3, in: directory)
        var builds = 0
        #expect(MacOSPrelinkedObjects.resolve(
            inputs: inputs, cacheDirectory: cache,
            driver: try makeDriver(in: directory), target: "arm64-apple-macosx11.0",
            environment: [:],
            build: { _, _ in builds += 1 }
        ) == nil)
        #expect(builds == 0)
    }

    @Test
    func cachedObjectIsOwnerOnly() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let inputs = try makeInputs(3, in: directory)
        let resolved = try #require(MacOSPrelinkedObjects.resolve(
            inputs: inputs, cacheDirectory: cache,
            driver: try makeDriver(in: directory), target: "arm64-apple-macosx11.0",
            environment: [:]
        ) { _, temporary in
            try Data("merged".utf8).write(to: temporary)
        })
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved)
        #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
    }
}
