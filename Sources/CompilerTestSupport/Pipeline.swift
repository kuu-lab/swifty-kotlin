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

func defaultTargetTriple() -> TargetTriple {
    TargetTriple.hostDefault()
}

/// `allowDefaultStdlibLibrary` defaults to `false` here: test targets that
/// inspect KIR callee names or symbol flags want the bundled stdlib compiled
/// from source, which is what `false` selects. `CompilerBackendTests` wants
/// the opposite default (the precompiled artifact) and keeps its own thin
/// wrapper in `Tests/CompilerBackendTests/Integration/TestSupport/Pipeline.swift`.
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

func makeContextFromSource(
    _ source: String,
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    emit: EmitMode = .kirDump,
    allowDefaultStdlibLibrary: Bool = false
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

func makeKIRContext(from context: CompilationContext, sema: SemaModule? = nil) -> KIRContext {
    KIRContext(
        diagnostics: context.diagnostics,
        options: context.options,
        interner: context.interner,
        sema: sema ?? context.sema
    )
}

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
