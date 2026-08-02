import Foundation
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimePathTests {
    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func extractStringRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func makePathRaw(_ value: String) -> Int {
        kk_path_new(makeStringRaw(value))
    }

    @Test
    func testPathInvariantSeparatorsPathRewritesBackslashes() {
        #expect(
            extractStringRaw(kk_path_invariantSeparatorsPath(makePathRaw(#"C:\tmp\archive.tar.gz"#)))
                == "C:/tmp/archive.tar.gz"
        )
        #expect(
            extractStringRaw(kk_path_invariantSeparatorsPath(makePathRaw("/tmp/archive.tar.gz")))
                == "/tmp/archive.tar.gz"
        )
    }

    @Test
    func testPathInvariantSeparatorsPathStringRewritesBackslashes() {
        #expect(
            extractStringRaw(kk_path_invariantSeparatorsPathString(makePathRaw(#"C:\tmp\archive.tar.gz"#)))
                == "C:/tmp/archive.tar.gz"
        )
    }

    @Test
    func testPathStringReturnsRawPathString() {
        #expect(
            extractStringRaw(kk_path_pathString(makePathRaw(#"C:\tmp\archive.tar.gz"#)))
                == #"C:\tmp\archive.tar.gz"#
        )
        #expect(
            extractStringRaw(kk_path_pathString(makePathRaw("/tmp/archive.tar.gz")))
                == "/tmp/archive.tar.gz"
        )
    }

    @Test
    func testPathNameReturnsLastComponent() {
        #expect(
            extractStringRaw(kk_path_name(makePathRaw("/tmp/archive.tar.gz")))
                == "archive.tar.gz"
        )
    }

    @Test
    func testPathNameWithoutExtensionReturnsLastComponentStem() {
        #expect(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/archive.tar.gz")))
                == "archive.tar"
        )
        #expect(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/README")))
                == "README"
        )
        #expect(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/.gitignore")))
                == ""
        )
    }

    @Test
    func testPathExtensionReturnsLastComponentExtension() {
        #expect(
            extractStringRaw(kk_path_extension(makePathRaw("/tmp/archive.tar.gz")))
                == "gz"
        )
        #expect(
            extractStringRaw(kk_path_extension(makePathRaw("/tmp/README")))
                == ""
        )
        #expect(
            extractStringRaw(kk_path_extension(makePathRaw("/tmp/.gitignore")))
                == "gitignore"
        )
        #expect(
            extractStringRaw(kk_path_extension(makePathRaw("/tmp/file.kt")))
                == "kt"
        )
    }

    @Test
    func testPathFactoryWriteTextAndAppendTextRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = kk_path_get(makeStringRaw(fileURL.path))
        #expect(extractStringRaw(kk_path_toString(pathRaw)) == fileURL.path)

        var thrown = 0
        #expect(kk_path_writeText(pathRaw, makeStringRaw("alpha"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha")

        let appendedPathRaw = kk_path_appendText_default(pathRaw, makeStringRaw("\nbeta"), &thrown)
        #expect(extractStringRaw(kk_path_toString(appendedPathRaw)) == fileURL.path)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta")
    }

    @Test
    func testPathDeleteIfExistsRemovesExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)

        #expect(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)) == 1)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)) == 0)
    }

    @Test
    func testPathNotExistsReturnsTrueForMissingPath() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Sanity: path must not exist before the assertion.
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let pathRaw = makePathRaw(fileURL.path)
        #expect(kk_unbox_bool(kk_path_notExists(pathRaw, 0)) == 1)
    }

    @Test
    func testPathNotExistsReturnsFalseForExistingPath() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        #expect(kk_unbox_bool(kk_path_notExists(pathRaw, 0)) == 0)
    }

    // STDLIB-IO-PATH-FN-040: Path.writeLines(Iterable)
    @Test
    func testPathWriteLinesIterableCreatesFileWithLines() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let linesRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeStringRaw("alpha"),
            makeStringRaw("beta"),
            makeStringRaw("gamma"),
        ]))
        var thrown = 0
        let returned = kk_path_writeLines_iterable(pathRaw, linesRaw, 0, 0, &thrown)
        #expect(thrown == 0)
        #expect(returned == pathRaw)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta\ngamma\n")
    }

    @Test
    func testPathWriteLinesIterableOverwritesExistingContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let linesRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeStringRaw("new"),
            makeStringRaw("lines"),
        ]))
        var thrown = 0
        _ = kk_path_writeLines_iterable(pathRaw, linesRaw, 0, 0, &thrown)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "new\nlines\n")
    }

    @Test
    func testPathWriteLinesIterableEmptyListCreatesEmptyFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let linesRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        var thrown = 0
        _ = kk_path_writeLines_iterable(pathRaw, linesRaw, 0, 0, &thrown)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "")
    }
}
