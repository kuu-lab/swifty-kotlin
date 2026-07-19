import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePathCreateTempFileTests {
    @Test func pathCreateTempFilePrefixSuffixAttributesCreatesFile() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempFile_prefix_suffix_attributes(
            makeRuntimeString("kswiftk-"),
            makeRuntimeString(".data"),
            0,
            &thrown
        )
        let createdPath = try #require(runtimePathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        #expect(thrown == 0)
        #expect(createdPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect((createdPath as NSString).lastPathComponent.hasPrefix("kswiftk-"))
        #expect(createdPath.hasSuffix(".data"))
        #expect(FileManager.default.fileExists(atPath: createdPath))
    }

    @Test func pathCreateTempFilePrefixSuffixAttributesUsesDefaultsForNulls() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempFile_prefix_suffix_attributes(0, 0, 0, &thrown)
        let createdPath = try #require(runtimePathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        #expect(thrown == 0)
        #expect(createdPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect((createdPath as NSString).lastPathComponent.hasPrefix("tmp"))
        #expect(createdPath.hasSuffix(".tmp"))
        #expect(FileManager.default.fileExists(atPath: createdPath))
    }

    private func runtimePathString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimePathBox.self) else {
            return nil
        }
        return box.pathString
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }
}
