@testable import CompilerCore
@testable import CompilerBackend
import Foundation

private struct TestCompilationFailure: Error, CustomStringConvertible {
    let description: String
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

/// Compile Kotlin source through the KIR dump phase and assert success.
func assertKotlinCompilesToKIR(
    _ source: String,
    moduleName: String = "TestMod"
) throws {
    try withTemporaryFile(contents: source) { path in
        try assertKotlinInputsToKIR(inputs: [path], moduleName: moduleName)
    }
}

/// Compile multiple Kotlin sources through the KIR dump phase and assert success.
func assertKotlinSourcesToKIR(
    _ sources: [String],
    moduleName: String = "TestMod"
) throws {
    try withTemporaryFiles(contents: sources) { paths in
        try assertKotlinInputsToKIR(inputs: paths, moduleName: moduleName)
    }
}

private func assertKotlinInputsToKIR(
    inputs: [String],
    moduleName: String
) throws {
    let fm = FileManager.default
    let outputBase = fm.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).path
    let kirPath = outputBase + ".kir"
    defer { try? fm.removeItem(atPath: kirPath) }

    let options = makeTestOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: outputBase,
        emit: .kirDump
    )
    let result = makeTestDriver().runForTesting(options: options)

    guard result.exitCode == 0 else {
        let diagnostics = result.diagnostics
            .map { $0.code + ": " + $0.message }
            .joined(separator: ", ")
        throw TestCompilationFailure(
            description: "KIR compilation failed. Diagnostics: " + diagnostics
        )
    }
    guard !result.diagnostics.contains(where: { $0.severity == .error }) else {
        let errors = result.diagnostics
            .filter { $0.severity == .error }
            .map { $0.code + ": " + $0.message }
            .joined(separator: ", ")
        throw TestCompilationFailure(
            description: "Unexpected errors: " + errors
        )
    }
    guard fm.fileExists(atPath: kirPath) else {
        throw TestCompilationFailure(description: "KIR file not produced at " + kirPath)
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

        guard result.exitCode == 0 else {
            let diagnostics = result.diagnostics
                .map { $0.code + ": " + $0.message }
                .joined(separator: ", ")
            throw TestCompilationFailure(
                description: "Object compilation failed. Diagnostics: " + diagnostics
            )
        }
        guard !result.diagnostics.contains(where: { $0.severity == .error }) else {
            let errors = result.diagnostics
                .filter { $0.severity == .error }
                .map { $0.code + ": " + $0.message }
                .joined(separator: ", ")
            throw TestCompilationFailure(
                description: "Unexpected errors: " + errors
            )
        }
        guard fm.fileExists(atPath: objectPath) else {
            throw TestCompilationFailure(description: "Object file not produced at " + objectPath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
        guard !data.isEmpty else {
            throw TestCompilationFailure(description: "Object file is empty")
        }
    }
}
