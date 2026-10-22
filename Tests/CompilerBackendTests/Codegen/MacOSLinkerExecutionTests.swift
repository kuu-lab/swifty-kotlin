@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

#if os(macOS)
extension LinkPhaseIntegrationTests {
    @Test
    func linksAndRunsThroughClangWithCustomLibrariesAndQuotedOutputPath() throws {
        try withTemporaryFile(contents: "fun main() { println(42) }") { input in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("app with spaces").path
            let options = CompilerOptions(
                moduleName: "DirectClangLink", inputs: [input], outputPath: output,
                emit: .executable, libraryPaths: [directory.path], linkLibraries: ["sqlite3"],
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            // The second link must reuse the persisted driver plan as well as
            // exercise real runtime autolink records and the entry wrapper.
            for _ in 0..<2 {
                timer.beginPhase("Link")
                try LinkPhase().run(ctx)
                timer.endPhase()
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.stdout == "42\n")
            }
            let second = try #require(timer.phaseRecords.last)
            #expect(second.subRecords.contains { $0.name == "Link/clang" })
            #expect(second.subRecords.contains { $0.name == "prelinkedObjects" })
            #expect(!second.subRecords.contains { $0.name == "Link/swiftc-plan" || $0.name == "Link/swiftc" })
        }
    }
}
#endif
