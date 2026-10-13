@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct DefaultStdlibEmitModeTests {
    /// KUU-1960: non-executable outputs must use imported stdlib metadata and
    /// inline KIR without loading bundled source files into the user module.
    @Test(arguments: ["object", "llvmIR", "kirDump", "library"])
    func defaultArtifactProducesRequestedOutput(emitMode: String) throws {
        let emit = try #require(EmitMode(rawValue: emitMode))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFile(contents: """
        fun values(): String = listOf(1, 2, 3).map { it * 2 }.joinToString(",")
        fun main() { println(values()) }
        """) { path in
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DefaultStdlibConsumer",
                emit: emit,
                outputPath: directory.appendingPathComponent("output").path
            )
            #expect(ctx.options.stdlibLibraryPath != nil)
            #expect(!ctx.options.includeStdlib)
            #expect(ctx.sourceManager.fileIDs().count == 1)
            #expect(!ctx.sourceManager.fileIDs().contains {
                ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true
            })
            try assertNoDiagnosticErrors(ctx)

            switch emit {
            case .object:
                let data = try Data(contentsOf: URL(fileURLWithPath: try #require(ctx.generatedObjectPath)))
                assertIsNativeObjectFile(data)
            case .llvmIR:
                let ir = try String(contentsOfFile: try #require(ctx.generatedLLVMIRPath), encoding: .utf8)
                #expect(ir.contains("define "))
                #expect(ir.contains("declare "))
            case .kirDump:
                let dump = try String(contentsOf: directory.appendingPathComponent("output.kir"), encoding: .utf8)
                #expect(dump.contains("values"))
            case .library:
                #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("output.kklib/metadata.bin").path))
            case .executable:
                Issue.record("Unexpected executable mode")
            }
        }
    }

    /// Imported stdlib references in a user library must survive metadata
    /// serialization and link against the same stdlib artifact in a consumer.
    @Test
    func defaultArtifactLibraryLinksInExecutableConsumer() throws {
        try withCompiledLibrary(
            source: """
            package sample
            fun values(): String = listOf(1, 2, 3).map { it * 2 }.joinToString(",")
            """,
            moduleName: "DefaultStdlibLibrary"
        ) { libraryPath in
            try withTemporaryFile(contents: "import sample.values\nfun main() { println(values()) }") { path in
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let outputPath = directory.appendingPathComponent("consumer").path
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "DefaultStdlibLibraryConsumer",
                    emit: .executable,
                    outputPath: outputPath,
                    searchPaths: [libraryPath]
                )
                try runToKIR(ctx)
                try LoweringPhase().run(ctx)
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "2,4,6\n")
            }
        }
    }
}
