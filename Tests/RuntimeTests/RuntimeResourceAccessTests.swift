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

        #expect(kk_resource_exists(runtimeString("hello.txt")) != 0)

        var thrown = 0
        let textRaw = kk_readResourceAsText(runtimeString("hello.txt"), &thrown)
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

        let loaderRaw = kk_classloader_getSystemClassLoader()
        let pathRaw = kk_classloader_getResource(loaderRaw, runtimeString("bytes.bin"))
        #expect(stringValue(pathRaw) == fileURL.path)

        let streamRaw = kk_classloader_getResourceAsStream(loaderRaw, runtimeString("bytes.bin"))
        var thrown: Int = 0
        #expect(kk_input_stream_read(streamRaw, &thrown) == 65)
        #expect(kk_input_stream_read(streamRaw, &thrown) == 66)
        #expect(kk_input_stream_read(streamRaw, &thrown) == -1)
        #expect(kk_input_stream_close(streamRaw) == 0)
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
