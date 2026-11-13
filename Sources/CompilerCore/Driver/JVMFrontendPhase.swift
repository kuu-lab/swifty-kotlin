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
                lazyPaths.formUnion(o.jvmClasspath.map {
                    URL(fileURLWithPath: $0).standardizedFileURL.path
                })
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
            let source = sourceDeclarations(in: ctx)
            let imports = try JVMClasspathIndex.load(
                classpath, lazilyInjecting: lazyPaths,
                platformClassFiles: jdkClasspath?.classFiles ?? [],
                fallbackClassFiles: ctx.androidResourceLink?.classFiles ?? [],
                sourcePackages: source.packages, sourceClassNames: source.classes,
                requiredLazyClassNames: jdkClasspath?.requiredLazyClassNames ?? [],
                archiveCache: ctx.jvmClasspathArchiveCache
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

    private func sourceDeclarations(in ctx: CompilationContext) -> (packages: Set<String>, classes: Set<String>) {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        var packages: Set<String> = []
        var classes: Set<String> = []
        for file in ctx.sourceManager.fileIDs() where ctx.sourceManager.origin(of: file) == .user {
            let tokens = KotlinLexer(file: file, source: ctx.sourceManager.contents(of: file),
                                     interner: interner, diagnostics: diagnostics).lexAll()
            let (syntax, root) = KotlinParser(tokens: tokens, interner: interner, diagnostics: diagnostics).parseFile()
            let builder = BuildASTPhase()
            let children = syntax.children(of: root).compactMap { child -> NodeID? in
                guard case let .node(node) = child else { return nil }
                return node
            }
            let packageHeader = children.first { syntax.node($0).kind == .packageHeader }
            let package = packageHeader.map {
                builder.extractQualifiedPath(from: $0, in: syntax, interner: interner, isPackageHeader: true)
                    .map { interner.resolve($0) }.joined(separator: "/")
            } ?? ""
            packages.insert(package)
            func collect(_ node: NodeID, prefix: String) {
                switch syntax.node(node).kind {
                case .classDecl, .interfaceDecl, .objectDecl:
                    let name = interner.resolve(builder.declarationName(from: node, in: syntax, interner: interner))
                    guard !name.isEmpty else { return }
                    let binaryName = prefix + name
                    classes.insert(binaryName)
                    for case let .node(body) in syntax.children(of: node) where syntax.node(body).kind == .block {
                        for case let .node(child) in syntax.children(of: body) {
                            collect(child, prefix: binaryName + "$")
                        }
                    }
                default: break
                }
            }
            for node in children { collect(node, prefix: package.isEmpty ? "" : package + "/") }
        }
        return (packages, classes)
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
