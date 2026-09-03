@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation

func makeSemaModule(
    symbols: SymbolTable = SymbolTable(),
    types: TypeSystem = TypeSystem(),
    bindings: BindingTable = BindingTable(),
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> (ctx: SemaModule, symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
    CompilerTestSupport.makeSemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)
}

func defaultTargetTriple() -> TargetTriple {
    CompilerTestSupport.defaultTargetTriple()
}

/// CompilerCoreTests default to compiling the bundled stdlib from source
/// (`allowDefaultStdlibLibrary: false`) because most Core tests inspect KIR
/// callee names in their original Kotlin source form (e.g. `"map"`), which
/// only holds when the stdlib is compiled alongside the test input rather
/// than linked from the precompiled artifact.
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

func makeContextFromSource(
    _ source: String,
    frontendFlags: [String] = [],
    emit: EmitMode = .kirDump,
    allowDefaultStdlibLibrary: Bool = false
) -> CompilationContext {
    CompilerTestSupport.makeContextFromSource(
        source,
        frontendFlags: frontendFlags,
        emit: emit,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
}

func makeContextFromSources(
    _ sources: [String],
    allowDefaultStdlibLibrary: Bool = false
) -> CompilationContext {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fakePaths = sources.indices.map { index in
        tempDir.appendingPathComponent("input\(index).kt").path
    }
    let ctx = makeCompilationContext(
        inputs: fakePaths,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    for (path, source) in zip(fakePaths, sources) {
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    }
    return ctx
}
