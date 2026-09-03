@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache

func makeSemaModule(
    symbols: SymbolTable = SymbolTable(),
    types: TypeSystem = TypeSystem(),
    bindings: BindingTable = BindingTable(),
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> (ctx: SemaModule, symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
    CompilerTestSupport.makeSemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)
}

/// Backend tests need the precompiled shared stdlib artifact on disk for most
/// compilations (codegen/linking exercise the actual object-level stdlib, not
/// just bundled Kotlin sources), so preparing it is an eager side effect of
/// resolving the target triple, matching every call path below.
func defaultTargetTriple() -> TargetTriple {
    TestStdlibCache.shared.prepare()
    return CompilerTestSupport.defaultTargetTriple()
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

/// CompilerBackendTests default to allowing the precompiled stdlib artifact
/// (`allowDefaultStdlibLibrary: true`) since most Backend/codegen tests link
/// the actual object-level stdlib rather than compiling bundled Kotlin
/// sources. Because of that, KIR callee names seen by these tests are the
/// precompiled artifact's mangled symbols (e.g. `kk_fn_map_123`, not `map`)
/// — see `isKotlinCallee`/`containsKotlinCallee` in KIRAndLLVM.swift.
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

func runFrontend(_ ctx: CompilationContext) throws {
    try CompilerTestSupport.runFrontend(ctx)
}

func runSema(_ ctx: CompilationContext) throws {
    try CompilerTestSupport.runSema(ctx)
}

func runToKIR(_ ctx: CompilationContext) throws {
    try CompilerTestSupport.runToKIR(ctx)
}

func runToLowering(_ ctx: CompilationContext) throws {
    try CompilerTestSupport.runToLowering(ctx)
}

/// Compiles `source` into a real ".kklib" library on disk and passes its
/// directory path to `body`, cleaning up afterward.
func withCompiledLibrary(
    source: String,
    moduleName: String,
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
            outputPath: libraryBase
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
