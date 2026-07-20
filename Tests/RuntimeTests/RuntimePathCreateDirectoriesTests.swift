import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePathCreateDirectoriesTests {
    @Test func pathCreateDirectoriesAttributesCreatesDirectoryTree() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedURL = rootURL.appendingPathComponent("a").appendingPathComponent("b")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(nestedURL.path)
        let resultRaw = kk_path_createDirectories_attributes(pathRaw, 0, &thrown)

        var isDirectory: ObjCBool = false
        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        #expect(FileManager.default.fileExists(atPath: nestedURL.path, isDirectory: &isDirectory))
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
}
