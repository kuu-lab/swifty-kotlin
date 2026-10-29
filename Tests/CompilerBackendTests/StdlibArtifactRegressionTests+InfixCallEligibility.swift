@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true], [0, 2])
    func testSoftKeywordInfixCalleeThroughSourceAndFreshArtifact(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        if !fromSource { TestStdlibCache.shared.prepare() }
        let artifactPath = fromSource ? nil : try #require(CompilerOptions.defaultStdlibLibraryPath)
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = repoRoot.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/KUU-2448")
        let cases: [(String, [String])] = [
            ("upstream", [
                fixtureRoot.appendingPathComponent("kt628.kt").path,
                fixtureRoot.appendingPathComponent("upstreamRunner.kt").path,
            ]),
            ("minimal-and-controls", [
                fixtureRoot.appendingPathComponent("minimal.kt").path,
                fixtureRoot.appendingPathComponent("minimalAndControlsRunner.kt").path,
            ]),
        ]

        for (name, inputs) in cases {
            let output = directory.appendingPathComponent(name).path
            let options = CompilerOptions(
                moduleName: "KUU2448_\(name)", inputs: inputs,
                outputPath: output, emit: .executable, target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: fromSource, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr for \(name): \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "OK\n", "Unexpected output for \(name)")
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func testInfixEligibilityThroughSourceAndFreshArtifact(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let original = repoRoot.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/InfixCallEligibility/infixFunctionOverBuiltinMember.kt"
        ).path
        let consumer = directory.appendingPathComponent("consumer.kt").path
        try "fun main() { println(box()) }".write(toFile: consumer, atomically: true, encoding: .utf8)
        let cases: [(String, [String], String)] = [
            ("original", [original, consumer], "OK\n"),
            ("priority", [repoRoot.appendingPathComponent(
                "Scripts/diff_cases/infix_extension_over_non_infix_member.kt"
            ).path], "extension\nmember\nmember\nextension\n10\n20\n1\n2\n"),
        ]
        for (name, inputs, expected) in cases {
            let output = directory.appendingPathComponent(name).path
            let options = CompilerOptions(
                moduleName: "InfixEligibility_\(name)", inputs: inputs,
                outputPath: output, emit: .executable, target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: fromSource, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == expected, "Unexpected output for \(name)")
        }
    }
}
