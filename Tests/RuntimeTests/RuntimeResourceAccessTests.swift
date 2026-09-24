import Foundation
@testable import Runtime
import Testing

private func resetRuntimeResourceAccessTestState() {
    unsetenv("KSWIFTK_RESOURCE_ROOT")
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeResourceAccessTestState))
struct RuntimeResourceAccessTests {
    @Test func resourceExistsAndReadAsText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
        }

        let fileURL = dir.appendingPathComponent("hello.txt")
        try "hello resource".write(to: fileURL, atomically: true, encoding: .utf8)
        setenv("KSWIFTK_RESOURCE_ROOT", dir.path, 1)

        #expect(__kk_resource_exists(runtimeString("hello.txt")) != 0)

        var thrown = 0
        let textRaw = __kk_readResourceAsText(runtimeString("hello.txt"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(textRaw) == "hello resource")
    }

    @Test func classLoaderReturnsStreamAndPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
        }

        let fileURL = dir.appendingPathComponent("bytes.bin")
        try Data([65, 66]).write(to: fileURL)
        setenv("KSWIFTK_RESOURCE_ROOT", dir.path, 1)

        let loaderRaw = __kk_classloader_getSystemClassLoader()
        let pathRaw = __kk_classloader_getResource(loaderRaw, runtimeString("bytes.bin"))
        #expect(stringValue(pathRaw) == fileURL.path)

        let streamRaw = __kk_classloader_getResourceAsStream(loaderRaw, runtimeString("bytes.bin"))
        var thrown: Int = 0
        #expect(__kk_input_stream_read(streamRaw, &thrown) == 65)
        #expect(__kk_input_stream_read(streamRaw, &thrown) == 66)
        #expect(__kk_input_stream_read(streamRaw, &thrown) == -1)
        #expect(__kk_input_stream_close(streamRaw) == 0)
    }

    @Test func resourceAccessRejectsSymlinksAndParentTraversal() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("resources", isDirectory: true)
        let outside = base.appendingPathComponent("secret.txt")
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "outside secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("file-link.txt"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("directory-link", isDirectory: true),
            withDestinationURL: base
        )
        setenv("KSWIFTK_RESOURCE_ROOT", root.path, 1)
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(kk_unbox_bool(__kk_resource_exists(runtimeString("file-link.txt"))) == 0)
        #expect(kk_unbox_bool(__kk_resource_exists(runtimeString("directory-link/secret.txt"))) == 0)
        #expect(kk_unbox_bool(__kk_resource_exists(runtimeString("../secret.txt"))) == 0)

        let loaderRaw = __kk_classloader_getSystemClassLoader()
        #expect(__kk_classloader_getResource(loaderRaw, runtimeString("file-link.txt")) == runtimeNullSentinelInt)
        #expect(__kk_classloader_getResourceAsStream(loaderRaw, runtimeString("directory-link/secret.txt")) == runtimeNullSentinelInt)

        var thrown = 0
        let textRaw = __kk_readResourceAsText(runtimeString("file-link.txt"), &thrown)
        #expect(thrown != 0)
        #expect(stringValue(textRaw).isEmpty)
    }

    @Test func nestedRegularResourceRemainsReadable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = dir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "nested resource".write(
            to: nested.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        setenv("KSWIFTK_RESOURCE_ROOT", dir.path, 1)

        var thrown = 0
        let textRaw = __kk_readResourceAsText(runtimeString("nested/hello.txt"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(textRaw) == "nested resource")
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
