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

/// Does not prepare the shared precompiled stdlib artifact as a side effect —
/// callers that need it (because they default to
/// `allowDefaultStdlibLibrary: true`) are responsible for calling
/// `TestStdlibCache.shared.prepare()` themselves.
func defaultTargetTriple() -> TargetTriple {
    TargetTriple.hostDefault()
}

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
    try runFrontendSyntaxPhases(ctx)
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

/// See `makeCompilationContext` for why `allowDefaultStdlibLibrary` has no
/// default here.
func makeContextFromSource(
    _ source: String,
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    emit: EmitMode = .kirDump,
    allowDefaultStdlibLibrary: Bool
) -> CompilationContext {
    let fakePath = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(
        inputs: [fakePath],
        moduleName: moduleName,
        emit: emit,
        frontendFlags: frontendFlags,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    return ctx
}

/// A stdlib-free `CompilationContext` over a single virtual source, shared by
/// bound-identity regression tests across test targets.
func makeBoundIdentityContext(_ source: String) -> CompilationContext {
    let path = "/virtual/bound-identity.kt"
    let context = makeCompilationContext(
        inputs: [path],
        includeStdlib: false,
        allowDefaultStdlibLibrary: false
    )
    _ = context.sourceManager.addFile(path: path, contents: .init(source.utf8))
    return context
}

/// A `KIRContext` for tests that drive a single `KIRPass` directly instead of
/// the whole `LoweringPhase`. `moduleName` is defaulted because no lowering
/// pass reads `CompilerOptions` — nothing under `Sources/CompilerCore/Lowering`
/// touches `options`, so the value is unobservable from a pass test.
func makeKIRContext(
    moduleName: String = "KIRTest",
    interner: StringInterner,
    sema: SemaModule? = nil,
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> KIRContext {
    let ctx = makeCompilationContext(
        inputs: [],
        moduleName: moduleName,
        interner: interner,
        diagnostics: diagnostics,
        allowDefaultStdlibLibrary: false
    )
    return makeKIRContext(from: ctx, sema: sema)
}

/// The `KIRContext` that `LoweringPhase.run` builds for `context`, for tests
/// that run one pass against an already-built `CompilationContext`.
func makeKIRContext(from context: CompilationContext, sema: SemaModule? = nil) -> KIRContext {
    KIRContext(
        diagnostics: context.diagnostics,
        options: context.options,
        interner: context.interner,
        sema: sema ?? context.sema
    )
}

/// Run `LoweringPhase` over a hand-built `module`, the shape every
/// pass-level lowering test needs.
@discardableResult
func runLowering(
    module: KIRModule,
    interner: StringInterner,
    moduleName: String,
    emit: EmitMode = .kirDump,
    sema: SemaModule? = nil,
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) throws -> CompilationContext {
    let ctx = makeCompilationContext(
        inputs: [],
        moduleName: moduleName,
        emit: emit,
        interner: interner,
        diagnostics: diagnostics,
        allowDefaultStdlibLibrary: false
    )
    ctx.kir = module
    ctx.sema = sema
    try LoweringPhase().run(ctx)
    return ctx
}
