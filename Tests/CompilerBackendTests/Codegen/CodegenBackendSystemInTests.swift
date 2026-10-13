#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSystemInTests {
    @Test(arguments: [0, 2], [false, true])
    func propertyIsAvailable(optimization: Int, stdlibFromSource: Bool) throws {
        try runWithInput(
            try diffCaseSource("system_in.kt", file: #filePath),
            optimization: optimization,
            stdlibFromSource: stdlibFromSource,
            invocation: "\"$1\" < /dev/null",
            expected: "true\n"
        )
    }

    @Test(arguments: [0, 2], [false, true])
    func byteReadsShareTheConsoleCursor(optimization: Int, stdlibFromSource: Bool) throws {
        try runWithInput(
            """
            fun main() {
                val input: java.io.InputStream = System.`in`
                println(input === java.lang.System.`in`)
                println(input.read())
                println(readLine())
                println(input.read())
                println(input.read())
                println(input.read())
                println(input.read())
                println(readLine())
            }
            """,
            optimization: optimization,
            stdlibFromSource: stdlibFromSource,
            invocation: "printf 'Aline\\n\\377B' | \"$1\"",
            expected: "true\n65\nline\n255\n66\n-1\n-1\nnull\n"
        )
    }

    private func runWithInput(
        _ source: String,
        optimization: Int,
        stdlibFromSource: Bool,
        invocation: String,
        expected: String
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let library = stdlibFromSource ? nil : try testStdlibArtifactPath()
        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let ctx = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU2017SystemIn",
                outputPath: output,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: library
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", invocation, "sh", output],
                timeout: 10
            )
            #expect(result.exitCode == 0)
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
