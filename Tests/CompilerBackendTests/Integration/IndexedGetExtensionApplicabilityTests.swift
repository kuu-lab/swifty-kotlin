@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct IndexedGetExtensionApplicabilityTests {
    @Test
    func projectedMapLookupRejectsUnrelatedKeys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        for (index, source) in [
            "fun main() { println(mapOf('(' to ')')[1]) }",
            "fun main() { println(mutableMapOf('(' to ')')[\"wrong\"]) }",
        ].enumerated() {
            let input = directory.appendingPathComponent("invalid\(index).kt").path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "InvalidMapKey", inputs: [input],
                outputPath: directory.appendingPathComponent("invalid\(index)").path,
                emit: .executable, target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            ))
            #expect(result.exitCode != 0, "Unrelated map key must be rejected: \(source)")
            #expect(result.diagnostics.contains { $0.severity == .error })
        }
    }

    @Test
    func importedUserOperatorRequiresLexicalImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Foreign").path
        try "package foreign\noperator fun List<Int>.get(key: String): Int = 7\n"
            .write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "Foreign", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib
        )))

        for imported in [false, true] {
            let input = directory.appendingPathComponent("consumer\(imported).kt").path
            let output = directory.appendingPathComponent("consumer\(imported)").path
            try ((imported ? "import foreign.get\n" : "") + "fun main() { println(listOf(1)[\"key\"]) }\n")
                .write(toFile: input, atomically: true, encoding: .utf8)
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "Consumer", inputs: [input], outputPath: output, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            ))
            if imported {
                try assertCompilationSucceeded(result)
                let execution = try CommandRunner.run(executable: output, arguments: [])
                #expect(execution.exitCode == 0)
                #expect(execution.stdout == "7\n")
                #expect(execution.stderr.isEmpty)
            } else {
                #expect(result.exitCode != 0, "Unimported operator must not be visible")
                #expect(result.diagnostics.contains { $0.severity == .error })
            }
        }
    }

    @Test(arguments: [true, false], [0, 2])
    func inapplicableMembersAllowOperatorExtensions(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = repository.appendingPathComponent(
            "Scripts/diff_cases/indexed_get_extension_applicability.kt"
        ).path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("indexed-get").path
        let options = CompilerOptions(
            moduleName: "IndexedGetExtensionApplicability",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stderr.isEmpty, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stdout == "null\n)\n)\nnull\nnull\n)\nnull\n42\n9\n9\n9\n9\n9\n7\n11\n23\n33\n41\ntrue\n",
                "fromSource=\(fromSource), O\(optimization): \(result.stdout)")
    }
}
