#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct WasmLibraryBodyImportTests {
    @Test
    func nonVirtualMemberBodyShipsInWasmLibraryAndMaterializesInConsumer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let librarySource = """
        package test

        class Box {
            companion object {
                fun parse(value: String): String = value + "!"
            }
        }
        """
        let librarySourcePath = directory.appendingPathComponent("Library.kt")
        try librarySource.write(to: librarySourcePath, atomically: true, encoding: .utf8)

        let libraryBase = directory.appendingPathComponent("BoxLib")
        let libraryPath = libraryBase.appendingPathExtension("kklib").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "BoxLib",
            inputs: [librarySourcePath.path],
            outputPath: libraryBase.path,
            emit: .library,
            target: .wasmWASI,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )))

        let metadata = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
        let parseRecord = try #require(MetadataDecoder().decode(metadata).first {
            $0.kind == .function && $0.fqName == "test.Box.Companion.parse"
        })
        let linkName = try #require(parseRecord.externalLinkName)
        let kirPath = libraryPath + "/inline-kir/" + MetadataEncoder.inlineKIRFileName(for: linkName)
        #expect(FileManager.default.fileExists(atPath: kirPath))

        let consumerSource = """
        import test.Box

        fun main() {
            val x = Box.parse("x")
        }
        """
        let consumerSourcePath = directory.appendingPathComponent("Main.kt")
        try consumerSource.write(to: consumerSourcePath, atomically: true, encoding: .utf8)
        let wasmPath = directory.appendingPathComponent("main.wasm")
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "BoxConsumer",
            inputs: [consumerSourcePath.path],
            outputPath: wasmPath.path,
            emit: .executable,
            searchPaths: [libraryPath],
            target: .wasmWASI,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )))

        let wasm = try Data(contentsOf: wasmPath)
        #expect(wasm.range(of: Data("$stub_\(linkName)".utf8)) == nil)
    }
}
#endif
