#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

/// Create a ``CompilerDriver`` instance configured for testing.
func makeTestDriver() -> CompilerDriver {
    CompilerDriver()
}

/// Build ``CompilerOptions`` for test compilation.
func makeTestOptions(
    moduleName: String,
    inputs: [String],
    outputPath: String,
    emit: EmitMode,
    allowDefaultStdlibLibrary: Bool = true
) -> CompilerOptions {
    if allowDefaultStdlibLibrary {
        TestStdlibCache.shared.prepare()
    }
    return CompilerOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
}

/// Compile Kotlin source through the KIR dump phase and assert success.
func assertKotlinCompilesToKIR(
    _ source: String,
    moduleName: String = "TestMod",
    sourceLocation: Testing.SourceLocation = #_sourceLocation,
    allowDefaultStdlibLibrary: Bool = false
) throws {
    try withTemporaryFile(contents: source) { path in
        try assertKotlinInputsToKIR(
            inputs: [path],
            moduleName: moduleName,
            sourceLocation: sourceLocation,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

/// Compile multiple Kotlin sources through the KIR dump phase and assert success.
func assertKotlinSourcesToKIR(
    _ sources: [String],
    moduleName: String = "TestMod",
    sourceLocation: Testing.SourceLocation = #_sourceLocation,
    allowDefaultStdlibLibrary: Bool = false
) throws {
    try withTemporaryFiles(contents: sources) { paths in
        try assertKotlinInputsToKIR(
            inputs: paths,
            moduleName: moduleName,
            sourceLocation: sourceLocation,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

private func assertKotlinInputsToKIR(
    inputs: [String],
    moduleName: String,
    sourceLocation: Testing.SourceLocation,
    allowDefaultStdlibLibrary: Bool = false
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
        emit: .kirDump,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    let result = makeTestDriver().runForTesting(options: options)

    #expect(result.exitCode == 0,
            "KIR compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })",
            sourceLocation: sourceLocation)
    #expect(!result.diagnostics.hasError,
            "Unexpected errors: \(result.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })",
            sourceLocation: sourceLocation)
    #expect(fm.fileExists(atPath: kirPath),
            "KIR file not produced at \(kirPath)",
            sourceLocation: sourceLocation)
}

#endif
