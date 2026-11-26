#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite
struct IncrementalCacheDescriptorLeakTests {
    @Test
    func testLoadingCachedStateClosesCacheDirectoryDescriptors() throws {
        let root = NSTemporaryDirectory() + "IncrementalCacheDescriptorLeak_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let cachePath = root + "/cache"
        let sourceFile = root + "/main.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "M",
            inputs: [sourceFile],
            outputPath: root + "/out",
            emit: .executable,
            target: TargetTriple.hostDefault(),
            includeStdlib: false
        )

        let writer = IncrementalCompilationCache(cachePath: cachePath)
        writer.computeCurrentFingerprints(for: [sourceFile])
        writer.saveState(
            dependencyGraph: DependencyGraph(),
            options: options,
            frontendState: IncrementalFrontendState(
                buildConfigurationHash: writer.buildConfigurationHash(for: options),
                internerValues: [],
                files: [],
                arenaSnapshot: ASTArena().snapshot(),
                activeDeclsByFileRawID: [:],
                tokenCountsByFileRawID: [:],
                declarationCount: 0,
                tokenCount: 0
            )
        )

        let reader = IncrementalCompilationCache(cachePath: cachePath)
        reader.loadPreviousState()
        try #require(reader.hasPreviousCache)
        try #require(reader.loadFrontendState(for: options) != nil)

        #expect(openDescriptorCount(referringTo: cachePath) == 0)
    }

    private func openDescriptorCount(referringTo path: String) -> Int {
        var target = stat()
        guard stat(path, &target) == 0 else { return 0 }
        #if canImport(Darwin)
        let descriptorDirectory = "/dev/fd"
        #else
        let descriptorDirectory = "/proc/self/fd"
        #endif
        let descriptors = (try? FileManager.default.contentsOfDirectory(atPath: descriptorDirectory)) ?? []
        return descriptors.compactMap { Int32($0) }.filter { descriptor in
            var info = stat()
            return fstat(descriptor, &info) == 0
                && info.st_dev == target.st_dev
                && info.st_ino == target.st_ino
        }.count
    }
}
#endif
