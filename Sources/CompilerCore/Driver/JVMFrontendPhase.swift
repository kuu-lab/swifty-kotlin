import Foundation

/// Only JVM-specific support declarations are injected. Native stdlib bodies
/// and Native KIR/ABI lowerings never participate in this route.
final class JVMPreparationPhase: CompilerPhase {
    static let name = "JVMPreparation"
    static let consolePath = "<kswiftk-jvm>/console.kt"

    func run(_ ctx: CompilationContext) throws {
        let o = ctx.options
        guard (!o.inputs.isEmpty || o.stdlibOnly), o.stdlibLibraryPath == nil,
              o.searchPaths.isEmpty, o.libraryPaths.isEmpty, o.linkLibraries.isEmpty,
              o.entryPointFQName == nil, o.incrementalCachePath == nil,
              o.frontendFlags.allSatisfy({
                  $0 == "time-phases" || $0 == "no-incremental" || $0 == "full-value-classes"
              }),
              o.irFlags.isEmpty, o.runtimeFlags.isEmpty, o.optLevel == .O0,
              !o.debugInfo, o.target == .hostDefault(),
              !ctx.sourceManager.containsFile(path: Self.consolePath) else {
            ctx.diagnostics.error("KSWIFTK-JVM-0001", "JVM requires source files and does not support Native libraries/target triples, custom entry points, incremental compilation, optimization, debug info or unsupported feature flags.", range: nil)
            return
        }
        do {
            let imports = try JVMClasspathIndex.load(o.jvmClasspath)
            ctx.jvmImports = imports
        } catch {
            ctx.diagnostics.error("KSWIFTK-JVM-0003", "Cannot read JVM classpath: \(error)", range: nil)
            return
        }
        if o.stdlibOnly {
            ctx.jvmRuntimeClassAliases = try JVMStdlibCatalog.manifest().runtimeClassAliases ?? [:]
            try injectJVMStdlibSources(ctx)
        }
        try JVMStdlibCatalog.injectDeclarations(into: ctx)
        try ctx.jvmImports?.injectJDKPlatformDeclarations(into: ctx)
        try ctx.jvmImports?.inject(into: ctx)
    }
}

final class JVMFrontendPhase: CompilerPhase {
    static let name = "JVMFrontend"

    func run(_ ctx: CompilationContext) throws {
        do {
            // Recursive AST emission needs the same stack headroom as Native KIR
            // lowering, including when invoked from a cooperative-pool thread.
            let work = JVMFrontendWork(context: ctx)
            ctx.jvmProgram = try LargeStackExecutor.run { try work.build() }
        } catch let error as JVMFrontendError {
            ctx.diagnostics.error("KSWIFTK-JVM-0001", error.message, range: error.range)
        }
    }
}

/// The phase exclusively owns the context until the large-stack worker joins.
private final class JVMFrontendWork: @unchecked Sendable {
    let context: CompilationContext
    init(context: CompilationContext) { self.context = context }
    func build() throws -> JVMProgram { try JVMProgramBuilder(context: context).build() }
}

struct JVMFrontendError: Error {
    let message: String
    var range: SourceRange? = nil
}
