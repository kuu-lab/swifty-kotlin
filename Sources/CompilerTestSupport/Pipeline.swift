@testable import CompilerCore
import Foundation

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

/// The host target triple used by test compilations. Does not prepare the
/// shared precompiled stdlib artifact as a side effect — callers that need
/// it (because they default to `allowDefaultStdlibLibrary: true`) are
/// responsible for calling `TestStdlibCache.shared.prepare()` themselves.
func defaultTargetTriple() -> TargetTriple {
    TargetTriple.hostDefault()
}

/// Build a `CompilationContext` for test compilation.
///
/// `allowDefaultStdlibLibrary` is intentionally required rather than
/// defaulted here: CompilerCoreTests and CompilerBackendTests want opposite
/// defaults (source-compiled bundled stdlib vs. the precompiled artifact),
/// so each test target supplies its own default via a thin local wrapper
/// around this function instead of sharing one.
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
    allowDefaultStdlibLibrary: Bool
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

/// Build a `CompilationContext` whose single input is `source`, injected
/// directly into the source manager rather than written to disk.
///
/// See `makeCompilationContext` for why `allowDefaultStdlibLibrary` has no
/// default here.
func makeContextFromSource(
    _ source: String,
    frontendFlags: [String] = [],
    emit: EmitMode = .kirDump,
    allowDefaultStdlibLibrary: Bool
) -> CompilationContext {
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(
        inputs: [fakePath],
        emit: emit,
        frontendFlags: frontendFlags,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    return ctx
}
