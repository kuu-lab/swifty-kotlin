@testable import CompilerCore
@testable import CompilerBackend
import Foundation

struct TestCompilationFailure: Error, CustomStringConvertible {
    let description: String
}

private func formatDiagnostics(_ diagnostics: [Diagnostic]) -> String {
    diagnostics
        .map { $0.code + ": " + $0.message }
        .joined(separator: ", ")
}

/// Create a ``CompilerDriver`` instance configured for testing with backend phases.
func makeTestDriver() -> CompilerDriver {
    CompilerDriver(backendPhases: makeBackendPhases)
}

/// Build ``CompilerOptions`` for test compilation.
func makeTestOptions(
    moduleName: String,
    inputs: [String],
    outputPath: String,
    emit: EmitMode
) -> CompilerOptions {
    CompilerOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple()
    )
}

/// Assert a driver run exited successfully with no error-severity diagnostics.
func assertCompilationSucceeded(
    _ result: (exitCode: Int, diagnostics: [Diagnostic]),
    context: String = "Compilation"
) throws {
    guard result.exitCode == 0 else {
        throw TestCompilationFailure(
            description: "\(context) failed. Diagnostics: " + formatDiagnostics(result.diagnostics)
        )
    }
    let errors = result.diagnostics.filter { $0.severity == .error }
    guard errors.isEmpty else {
        throw TestCompilationFailure(description: "Unexpected errors: " + formatDiagnostics(errors))
    }
}

/// Assert a compilation context accumulated no error-severity diagnostics.
func assertNoDiagnosticErrors(_ ctx: CompilationContext) throws {
    guard ctx.diagnostics.hasError else { return }
    throw TestCompilationFailure(
        description: "Unexpected diagnostics: " + formatDiagnostics(ctx.diagnostics.diagnostics)
    )
}

/// Compile Kotlin source through the KIR dump phase and assert success.
func assertKotlinCompilesToKIR(
    _ source: String,
    moduleName: String = "TestMod"
) throws {
    try withTemporaryFile(contents: source) { path in
        let fm = FileManager.default
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let kirPath = outputBase + ".kir"
        defer { try? fm.removeItem(atPath: kirPath) }

        let options = makeTestOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: outputBase,
            emit: .kirDump
        )
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result, context: "KIR compilation")

        guard fm.fileExists(atPath: kirPath) else {
            throw TestCompilationFailure(description: "KIR file not produced at " + kirPath)
        }
    }
}

/// Compile Kotlin source through object emission and assert a valid object file is produced.
func assertKotlinCompilesToObject(
    _ source: String,
    moduleName: String = "TestMod"
) throws {
    try withTemporaryFile(contents: source) { path in
        let fm = FileManager.default
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let objectPath = outputBase + ".o"
        defer { try? fm.removeItem(atPath: objectPath) }

        let options = makeTestOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: outputBase,
            emit: .object
        )
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result, context: "Object compilation")

        guard fm.fileExists(atPath: objectPath) else {
            throw TestCompilationFailure(description: "Object file not produced at " + objectPath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
        guard !data.isEmpty else {
            throw TestCompilationFailure(description: "Object file is empty")
        }
    }
}

/// Compile `source` to an executable, run it, and assert stdout equals `expectedOutput`.
func compileAndRunKotlin(
    _ source: String,
    expectedOutput: String,
    moduleName: String = "ExecTest"
) throws {
    try withTemporaryFile(contents: source) { path in
        let fm = FileManager.default
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? fm.removeItem(atPath: outputBase) }

        let options = makeTestOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: outputBase,
            emit: .executable
        )
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result)

        let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalized = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized == expectedOutput else {
            throw TestCompilationFailure(
                description: "Expected stdout '\(expectedOutput)' but got '\(normalized)'"
            )
        }
    }
}
