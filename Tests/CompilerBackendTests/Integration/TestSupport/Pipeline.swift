@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import TestStdlibCache

func makeSemaModule(
    symbols: SymbolTable = SymbolTable(),
    types: TypeSystem = TypeSystem(),
    bindings: BindingTable = BindingTable(),
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> (ctx: SemaModule, symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
    let ctx = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )
    return (ctx, symbols, types, StringInterner())
}

func defaultTargetTriple() -> TargetTriple {
    TestStdlibCache.shared.prepare()
    return TargetTriple.hostDefault()
}

/// Return the prepared stdlib artifact used by tests that inspect imported
/// stdlib symbols rather than injected Kotlin source declarations.
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
    let destination = outputPath ?? FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .path
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: destination,
        emit: emit,
        searchPaths: searchPaths,
        target: defaultTargetTriple(),
        frontendFlags: frontendFlags,
        irFlags: irFlags,
        includeStdlib: includeStdlib,
        stdlibOnly: stdlibOnly,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    return CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: diagnostics ?? DiagnosticEngine(),
        interner: interner ?? StringInterner()
    )
}

func runFrontend(_ ctx: CompilationContext) throws {
    try LoadSourcesPhase().run(ctx)
    try LexPhase().run(ctx)
    try ParsePhase().run(ctx)
    try BuildASTPhase().run(ctx)
}

func runSema(_ ctx: CompilationContext) throws {
    try runFrontend(ctx)
    try SemaPhase().run(ctx)
}

func runToKIR(_ ctx: CompilationContext) throws {
    try runSema(ctx)
    try BuildKIRPhase().run(ctx)
}

func runToLowering(_ ctx: CompilationContext) throws {
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
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
