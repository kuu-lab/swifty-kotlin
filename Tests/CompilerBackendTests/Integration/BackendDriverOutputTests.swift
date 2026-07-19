#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct BackendDriverOutputTests {

    // MARK: - Driver output (moved from CompilerCoreTests)

    @Test func testEmitObjectProducesMachOFile() throws {
        let source = "fun main() {}"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = makeTestOptions(
                moduleName: "ObjTest",
                inputs: [tempSourcePath],
                outputPath: outputURL.path,
                emit: .object
            )
            let exitCode = makeTestDriver().run(options: options)
            #expect(exitCode == 0)
            let data = try Data(contentsOf: outputURL)
            #expect(data.count >= 4)
            #if os(Linux)
                // ELF magic number
                #expect(Array(data.prefix(4)) == [0x7F, 0x45, 0x4C, 0x46])
            #else
                // Mach-O magic number
                #expect(Array(data.prefix(4)) == [0xCF, 0xFA, 0xED, 0xFE])
            #endif
        }
    }

    @Test func testEmitExecutableFailsWithoutMainFunction() throws {
        let source = "fun notMain() {}"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = makeTestOptions(
                moduleName: "ExeTest",
                inputs: [tempSourcePath],
                outputPath: outputURL.path,
                emit: .executable
            )
            let exitCode = makeTestDriver().run(options: options)
            #expect(exitCode == 1)
        }
    }

    // MARK: - Backend smoke tests (moved from SmokeTests)

    @Test func testSmokeDriverExecutableFailsWithoutMain() throws {
        try withTemporaryFile(contents: "fun helper() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase)
                try? fileManager.removeItem(atPath: outputBase + ".o")
            }

            let options = makeTestOptions(
                moduleName: "SmokeMissingMain",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)

            #expect(result.exitCode == 1)
            #expect(result.diagnostics.contains(where: { $0.code == "KSWIFTK-LINK-0002" }))
        }
    }

    @Test func testSmokeLLVMObjectEmissionProducesNativeObjectFile() throws {
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let objectPath = outputBase + ".o"
            defer {
                try? fileManager.removeItem(atPath: objectPath)
            }

            let options = makeTestOptions(
                moduleName: "SmokeLLVM",
                inputs: [path],
                outputPath: outputBase,
                emit: .object
            )
            let result = makeTestDriver().runForTesting(options: options)

            #expect(result.exitCode == 0)
            #expect(!result.diagnostics.contains(where: { $0.severity == .error }))
            let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
            #expect(data.count >= 4)
            #if os(Linux)
                // ELF magic number
                #expect(Array(data.prefix(4)) == [0x7F, 0x45, 0x4C, 0x46])
            #else
                // Mach-O magic number
                #expect(Array(data.prefix(4)) == [0xCF, 0xFA, 0xED, 0xFE])
            #endif
        }
    }
}
#endif
