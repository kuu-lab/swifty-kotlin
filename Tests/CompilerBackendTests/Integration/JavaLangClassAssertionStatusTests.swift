import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct JavaLangClassAssertionStatusTests {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/KUU-2041")
    }

    @Test
    func ordinaryJavaFunctionStillRequiresParentheses() throws {
        try withTemporaryFiles(contents: ["""
        class C
        fun C.java(): Int = 7
        fun invalid(c: C): Int = c.java
        fun valid(c: C): Int = c.java()
        """]) { inputs in
            let options = CompilerOptions(
                moduleName: "JavaInvocationControl",
                inputs: inputs,
                outputPath: inputs[0] + ".kir",
                emit: .kirDump,
                target: CompilerTestSupport.defaultTargetTriple(),
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(result.exitCode != 0)
            let errors = result.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0309")
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func classStatusAndUpstreamAssertionsFollowNativePolicy(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = fromSource ? nil : try testStdlibArtifactPath()
        func compile(_ names: [String], output: String) throws {
            let options = CompilerOptions(
                moduleName: "KUU2041",
                inputs: names.map { fixtures.appendingPathComponent($0).path },
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: library,
                allowDefaultStdlibLibrary: !fromSource
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        }

        // Keep the issue's exact compile-only reproducer, including its empty main.
        try compile(["minimal.kt"], output: directory.appendingPathComponent("minimal").path)
        let output = directory.appendingPathComponent("upstream").path
        try compile(["commonMain/commonFunctions.kt", "jvmMain/commonFunctions.kt", "Main.kt"], output: output)

        // Run separate processes so environment initialization is tested without
        // mutating the assertion state shared by the Swift test runner.
        let policies: [(environment: [String], enabled: Bool)] = [
            ([], false),
            (["KK_ASSERTIONS_ENABLED=0"], false),
            (["KK_ASSERTIONS_ENABLED=1"], true),
            (["KOTLIN_ASSERTIONS_ENABLED=false"], false),
            (["KK_ASSERTIONS_ENABLED=off", "KOTLIN_ASSERTIONS_ENABLED=on"], false),
        ]
        for policy in policies {
            let result = try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["-u", "KK_ASSERTIONS_ENABLED", "-u", "KOTLIN_ASSERTIONS_ENABLED"]
                    + policy.environment + [output]
            )
            let flag = policy.enabled ? "true" : "false"
            let expected = Array(repeating: flag, count: 6).joined(separator: "\n") + "\n"
                + (policy.enabled ? "1\nAssertion failed\ntrue\n" : "0\nnull\nfalse\n") + "3\n"
            #expect(result.exitCode == 0, "\(policy.environment): \(result.stderr)")
            #expect(result.stdout == expected, "\(policy.environment): \(result.stdout)")
            #expect(result.stderr.isEmpty, "\(result.stderr)")
        }
    }
}
