import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePathCreateFileTests {
    @Test func pathCreateFileAttributesCreatesEmptyFile() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("created.txt")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let resultRaw = kk_path_createFile_attributes(pathRaw, 0, &thrown)

        var isDirectory: ObjCBool = false
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        #expect(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        #expect(!isDirectory.boolValue)
        #expect((attributes[.size] as? NSNumber)?.uint64Value == 0)
    }

    @Test func pathCreateFileAttributesFailsWhenFileExists() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("existing.txt")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: fileURL)

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let resultRaw = kk_path_createFile_attributes(pathRaw, 0, &thrown)

        #expect(thrown != 0)
        #expect(resultRaw == pathRaw)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "kept")
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
