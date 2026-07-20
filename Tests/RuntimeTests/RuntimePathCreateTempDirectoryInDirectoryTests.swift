import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePathCreateTempDirectoryInDirectoryTests {
    @Test func pathCreateTempDirectoryDirectoryPrefixAttributesCreatesDirectoryInParent() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var thrown = 0
        let resultRaw = kk_path_createTempDirectory_directory_prefix_attributes(
            runtimeTestPathHandle(rootURL.path),
            makeRuntimeString("kswiftk-"),
            0,
            &thrown
        )
        let createdPath = extractStringRaw(kk_path_pathString(resultRaw))

        var isDirectory: ObjCBool = false
        #expect(thrown == 0)
        #expect((createdPath as NSString).deletingLastPathComponent == rootURL.path)
        #expect((createdPath as NSString).lastPathComponent.hasPrefix("kswiftk-"))
        #expect(FileManager.default.fileExists(atPath: createdPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func pathCreateTempDirectoryDirectoryPrefixAttributesUsesDefaultDirectoryForNull() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempDirectory_directory_prefix_attributes(0, makeRuntimeString("kswiftk-"), 0, &thrown)
        let createdPath = extractStringRaw(kk_path_pathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        var isDirectory: ObjCBool = false
        #expect(thrown == 0)
        #expect(createdPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect((createdPath as NSString).lastPathComponent.hasPrefix("kswiftk-"))
        #expect(FileManager.default.fileExists(atPath: createdPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeRuntimeString(path))
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func extractStringRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
