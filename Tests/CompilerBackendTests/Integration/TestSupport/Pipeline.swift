@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache

func defaultTargetTriple() -> TargetTriple {
    TestStdlibCache.shared.prepare()
    return CompilerTestSupport.defaultTargetTriple()
}

func testStdlibArtifactPath() throws -> String {
    _ = defaultTargetTriple()
    guard let path = CompilerOptions.defaultStdlibLibraryPath,
          FileManager.default.fileExists(atPath: path)
    else {
        throw CompilerPipelineError.invalidInput(
            "The shared stdlib artifact was not prepared for an artifact-backed test."
        )
    }
    return path
}

func makeArtifactCompilationContext(
    inputs: [String],
    moduleName: String = "TestModule",
    emit: EmitMode = .kirDump,
    outputPath: String? = nil,
    searchPaths: [String] = [],
    irFlags: [String] = [],
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    interner: StringInterner? = nil,
    diagnostics: DiagnosticEngine? = nil,
    stdlibOnly: Bool = false
) throws -> CompilationContext {
    makeCompilationContext(
        inputs: inputs,
        moduleName: moduleName,
        emit: emit,
        outputPath: outputPath,
        searchPaths: searchPaths,
        irFlags: irFlags,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        interner: interner,
        diagnostics: diagnostics,
        stdlibOnly: stdlibOnly,
        stdlibLibraryPath: try testStdlibArtifactPath()
    )
}

func makeCompilationContext(
    inputs: [String],
    moduleName: String = "TestModule",
    emit: EmitMode = .kirDump,
    outputPath: String? = nil,
    searchPaths: [String] = [],
    irFlags: [String] = [],
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    interner: StringInterner? = nil,
    diagnostics: DiagnosticEngine? = nil,
    stdlibOnly: Bool = false,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = true
) -> CompilationContext {
    TestStdlibCache.shared.prepare()
    return CompilerTestSupport.makeCompilationContext(
        inputs: inputs,
        moduleName: moduleName,
        emit: emit,
        outputPath: outputPath,
        searchPaths: searchPaths,
        irFlags: irFlags,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        interner: interner,
        diagnostics: diagnostics,
        stdlibOnly: stdlibOnly,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
}

func withCompiledLibrary(
    source: String,
    moduleName: String,
    includeStdlib: Bool = true,
    allowDefaultStdlibLibrary: Bool = true,
    frontendFlags: [String] = [],
    body: (String) throws -> Void
) throws {
    let libraryBase = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .path
    defer { try? FileManager.default.removeItem(atPath: libraryBase + ".kklib") }
    try withTemporaryFile(contents: source) { path in
        let ctx = makeCompilationContext(
            inputs: [path],
            moduleName: moduleName,
            emit: .library,
            outputPath: libraryBase,
            frontendFlags: frontendFlags,
            includeStdlib: includeStdlib,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
    }
    try body(libraryBase + ".kklib")
}

func makeContextFromSource(
    _ source: String,
    allowDefaultStdlibLibrary: Bool = true
) -> CompilationContext {
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(
        inputs: [fakePath],
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    return ctx
}
