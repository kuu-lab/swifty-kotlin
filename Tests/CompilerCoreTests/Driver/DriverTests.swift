#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct DriverTests {
    // MARK: - fallbackDiagnostic

    @Test
    func testFallbackDiagnosticForLoadError() throws {
        let error = CompilerPipelineError.loadError
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0001")
        #expect(result?.message.contains("loading input sources") == true)
    }

    @Test
    func testFallbackDiagnosticForInvalidInput() throws {
        let error = CompilerPipelineError.invalidInput("bad IR")
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0002")
        #expect(result?.message.contains("bad IR") == true)
    }

    @Test
    func testFallbackDiagnosticForOutputUnavailable() throws {
        let error = CompilerPipelineError.outputUnavailable
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0003")
        #expect(result?.message.contains("could not produce") == true)
    }

    @Test
    func testFallbackDiagnosticReturnsNilForNonPipelineError() {
        struct OtherError: Error {}
        let result = CompilerDriver.fallbackDiagnostic(for: OtherError())
        #expect(result == nil)
    }

    // MARK: - runForTesting

    @Test
    func testRunForTestingWithNoInputsEmitsError() {
        let driver = CompilerDriver()
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        #expect(result.exitCode == 1)
        #expect(result.diagnostics.contains(where: { $0.severity == .error }))
    }

    @Test
    func testRunForTestingWithNonExistentInputEmitsError() {
        let driver = CompilerDriver()
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: ["/nonexistent/path.kt"],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        #expect(result.exitCode == 1)
    }

    @Test
    func testRunForTestingWithValidKirDump() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = CompilerDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let result = driver.runForTesting(options: options)
            // KIR dump should succeed without LLVM
            #expect(result.exitCode == 0, "KIR dump should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    @Test
    func testRunForTestingReturnsDiagnosticsForInvalidProgram() throws {
        try withTemporaryFile(contents: "fun main() { val x: Int = \"wrong\" }") { path in
            let driver = CompilerDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let result = driver.runForTesting(options: options)
            // Should have diagnostics for the type mismatch
            #expect(!(result.diagnostics.isEmpty), "Expected diagnostics for invalid program, but got none")
        }
    }

    @Test(arguments: ["\n", "\r", "\r\n"], ["", "$$"])
    func testRunForTestingRejectsUnescapedStringLineBreaks(lineBreak: String, prefix: String) throws {
        let source = "fun main() { println(\(prefix)\"  indented" + lineBreak + "  text\") }"
        try withTemporaryFile(contents: source) { path in
            let outputPath = NSTemporaryDirectory() + "invalid_string_\(UUID().uuidString).kir"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                includeStdlib: false
            )
            let result = CompilerDriver().runForTesting(options: options)

            #expect(result.exitCode == 1)
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-LEX-0004" && $0.severity == .error })
            #expect(!FileManager.default.fileExists(atPath: outputPath))
        }
    }

    @Test
    func testRunFrontendDefaultStopsAfterParseError() {
        let path = NSTemporaryDirectory() + "frontend_parse_error_\(UUID().uuidString).kt"
        let source = """
        package demo

        }
        fun recovered(): Int = 42
        """
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [path],
            outputPath: "/dev/null",
            emit: .object,
            target: defaultTargetTriple(),
            includeStdlib: false
        )
        let result = CompilerDriver().runFrontend(
            options: options,
            inMemorySources: [path: Data(source.utf8)]
        )

        #expect(result.context.ast == nil, "Default frontend policy should remain fail-fast")
        #expect(result.context.sema == nil, "Default frontend policy should not run Sema")
        #expect(
            result.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0006" },
            "Expected parse recovery diagnostic: \(result.diagnostics.map(\.code))"
        )
    }

    // MARK: - BuildAST error continuation

    private func duplicateCompanionWithSemaErrorOptions(path: String) -> CompilerOptions {
        CompilerOptions(
            moduleName: "Test",
            inputs: [path],
            outputPath: "/dev/null",
            emit: .kirDump,
            target: defaultTargetTriple(),
            includeStdlib: false
        )
    }

    private let duplicateCompanionWithSemaErrorSource = """
        class C { companion object A; companion object B }
        fun bad() = unresolvedFunc()
        """

    @Test
    func testRunFrontendStillRunsSemaAfterBuildASTDiagnostic() {
        let path = NSTemporaryDirectory() + "frontend_buildast_error_\(UUID().uuidString).kt"
        let result = CompilerDriver().runFrontend(
            options: duplicateCompanionWithSemaErrorOptions(path: path),
            inMemorySources: [path: Data(duplicateCompanionWithSemaErrorSource.utf8)]
        )

        // A BuildAST-phase diagnostic (duplicate companion object) must not
        // suppress semantic diagnostics — kotlinc reports both together.
        #expect(
            result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0435" },
            "Expected duplicate companion diagnostic: \(result.diagnostics.map(\.code))"
        )
        #expect(
            result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" },
            "Expected unresolved function diagnostic: \(result.diagnostics.map(\.code))"
        )
        #expect(result.context.sema != nil, "Sema should run after BuildAST diagnostics")
    }

    @Test
    func testDriverRunStillRunsSemaAfterBuildASTDiagnostic() throws {
        let path = NSTemporaryDirectory() + "driver_buildast_error_\(UUID().uuidString).kt"
        try Data(duplicateCompanionWithSemaErrorSource.utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = CompilerDriver().runForTesting(
            options: duplicateCompanionWithSemaErrorOptions(path: path)
        )

        #expect(result.exitCode == 1)
        #expect(
            result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0435" },
            "Expected duplicate companion diagnostic: \(result.diagnostics.map(\.code))"
        )
        #expect(
            result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" },
            "Expected unresolved function diagnostic: \(result.diagnostics.map(\.code))"
        )
    }

    // MARK: - run

    @Test
    func testRunReturnsExitCode() {
        let driver = CompilerDriver()
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        // Use runForTesting to avoid printing diagnostics to stderr during tests
        let result = driver.runForTesting(options: options)
        #expect(result.exitCode == 1)
    }

}
#endif
