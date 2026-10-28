@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation

// Per-target defaults layer: `CompilerTestSupport` intentionally leaves
// `allowDefaultStdlibLibrary` without a default, and each test target supplies
// its own via these thin wrappers. CompilerCoreTests default to compiling the
// bundled stdlib from source (`false`) because most Core tests inspect KIR
// callee names in their original Kotlin source form (e.g. `"map"`), which only
// holds when the stdlib is compiled alongside the test input rather than
// linked from the precompiled artifact.
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
    allowDefaultStdlibLibrary: Bool = false
) -> CompilationContext {
    CompilerTestSupport.makeCompilationContext(
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

func makeContextFromSource(
    _ source: String,
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    emit: EmitMode = .kirDump,
    allowDefaultStdlibLibrary: Bool = false
) -> CompilationContext {
    CompilerTestSupport.makeContextFromSource(
        source,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        emit: emit,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
}

func makeContextFromSources(
    _ sources: [String],
    moduleName: String = "TestModule",
    allowDefaultStdlibLibrary: Bool = false
) -> CompilationContext {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fakePaths = sources.indices.map { index in
        tempDir.appendingPathComponent("input\(index).kt").path
    }
    let ctx = makeCompilationContext(
        inputs: fakePaths,
        moduleName: moduleName,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    for (path, source) in zip(fakePaths, sources) {
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    }
    return ctx
}
