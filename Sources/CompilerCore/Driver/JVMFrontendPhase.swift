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
                      || $0.hasPrefix("jobs=")
              }),
              o.irFlags.isEmpty, o.runtimeFlags.isEmpty, o.optLevel == .O0,
              !o.debugInfo, o.target == .hostDefault(),
              !ctx.sourceManager.containsFile(path: Self.consolePath) else {
            ctx.diagnostics.error("KSWIFTK-JVM-0001", "JVM requires source files and does not support Native libraries/target triples, custom entry points, incremental compilation, optimization, debug info or unsupported feature flags.", range: nil)
            return
        }
        do {
            var classpath = o.jvmClasspath
            var lazyPaths: Set<String> = []
            var jdkClasspath: JVMJDKClasspath?
            if !o.stdlibOnly && (o.emit == .jvmClass || o.emit == .jvmJar) {
                jdkClasspath = try JVMJDKClasspath.prepare(for: ctx)
            }
            if o.emit == .apk, o.android.resourcePath != nil {
                let toolchain = try AndroidSDKLocator.locate(
                    sdkPath: o.android.sdkPath, buildToolsVersion: o.android.buildToolsVersion,
                    compileSdk: o.android.compileSdk
                )
                ctx.androidResourceLink = try AndroidResourceLink.prepare(
                    options: o.android, toolchain: toolchain, phaseTimer: ctx.phaseTimer
                )
            }
            if o.emit == .dex || o.emit == .apk {
                // The Android framework resolves like any other classpath
                // dependency so `android.*` types are visible to Sema. The
                // same jar later serves as the d8 --lib bootclasspath. Its
                // classes are injected lazily: only the subset reachable
                // from user sources gets a Kotlin stub, since eagerly
                // importing thousands of framework classes exhausts the
                // symbol table.
                let androidJar = try ctx.androidResourceLink?.androidJarPath ?? AndroidSDKLocator.androidJarPath(
                    sdkPath: o.android.sdkPath,
                    compileSdk: o.android.compileSdk
                )
                let standardized = URL(fileURLWithPath: androidJar).standardizedFileURL.path
                lazyPaths.insert(standardized)
                if !classpath.contains(where: {
                    URL(fileURLWithPath: $0).standardizedFileURL.path == standardized
                }) {
                    classpath.append(androidJar)
                }
            }
            let imports = try JVMClasspathIndex.load(
                classpath, lazilyInjecting: lazyPaths,
                platformClassFiles: jdkClasspath?.classFiles ?? [],
                fallbackClassFiles: ctx.androidResourceLink?.classFiles ?? [],
                requiredLazyClassNames: jdkClasspath?.requiredLazyClassNames ?? []
            )
            ctx.jvmImports = imports
        } catch let error as AndroidSDKError {
            ctx.diagnostics.error("KSWIFTK-ANDROID-0001", error.description, range: nil)
            return
        } catch let error as AndroidPackagingError {
            ctx.diagnostics.error("KSWIFTK-ANDROID-0002", error.description, range: nil)
            return
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
        try ctx.jvmImports?.injectJDKStreamPlatformDeclarations(into: ctx)
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
