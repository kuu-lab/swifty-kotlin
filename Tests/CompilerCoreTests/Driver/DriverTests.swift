#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DriverTests {
    // MARK: - fallbackDiagnostic

    @Test
    func testFallbackDiagnosticForLoadError() throws {
        let error = CompilerPipelineError.loadError
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0001")
        #expect(try #require(result?.message.contains("loading input sources")))
    }

    @Test
    func testFallbackDiagnosticForInvalidInput() throws {
        let error = CompilerPipelineError.invalidInput("bad IR")
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0002")
        #expect(try #require(result?.message.contains("bad IR")))
    }

    @Test
    func testFallbackDiagnosticForOutputUnavailable() throws {
        let error = CompilerPipelineError.outputUnavailable
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        #expect(result != nil)
        #expect(result?.code == "KSWIFTK-PIPELINE-0003")
        #expect(try #require(result?.message.contains("could not produce")))
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

    // MARK: - CompilerDriver Init

    @Test
    func testCompilerDriverInit() {
        let driver = CompilerDriver()
        // Verify the driver works by running with empty inputs
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        #expect(result.exitCode == 1)
    }
}
#endif
