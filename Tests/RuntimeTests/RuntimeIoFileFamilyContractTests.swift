import Foundation
@testable import Runtime
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeIoFileFamilyContractTests {
    @Test
    func listDistinguishesMissingFromNonDirectoryTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data([1]).write(to: file)
        var thrown = 0
        _ = __kk_io_fs_list(runtimeMakeStringRaw(file.path + "/child"), &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
        _ = __kk_io_fs_list(runtimeMakeStringRaw(root.appendingPathComponent("absent").path), &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.files.FileNotFoundException")
        _ = __kk_io_fs_list(runtimeMakeStringRaw(root.path), &thrown)
        #expect(thrown == 0)
    }

    @Test
    func temporaryDirectoryBridgeUsesMatchingHostActual() {
        #if canImport(Darwin)
        let expected = NSTemporaryDirectory()
        #else
        let path = getenv("TMPDIR") ?? getenv("TMP")
        let expected = path.map { String(cString: $0) } ?? ""
        #endif
        let raw = __kk_io_fs_temporary_directory()
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) == expected)
        // Fresh-process environment variants are a separate finite CLI gate.
        // This test does not mutate process-wide environment during parallel tests.
    }
}
